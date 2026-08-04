#!/usr/bin/env python3
import sys
import os
import json
from PIL import Image
from surya.recognition import RecognitionPredictor
from surya.foundation import FoundationPredictor
from surya.detection import DetectionPredictor
from surya.common.surya.schema import TaskNames

# Fix encoding issues on Windows - set UTF-8 for stdout/stderr
if sys.platform == 'win32':
    import io
    # Reconfigure stdout and stderr to use UTF-8 encoding
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    elif not isinstance(sys.stdout, io.TextIOWrapper) or sys.stdout.encoding != 'utf-8':
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    elif not isinstance(sys.stderr, io.TextIOWrapper) or sys.stderr.encoding != 'utf-8':
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

if __name__ == "__main__":
    print("OCR: Starting Surya OCR script", flush=True)
    
    if len(sys.argv) < 3:
        error_msg = json.dumps({"error": "Usage: surya_ocr.py <image_path> <output_file_path>"})
        print(error_msg, file=sys.stderr)
        sys.exit(1)
    
    image_path = sys.argv[1]
    output_file_path = sys.argv[2]
    
    print(f"OCR: Image path: {image_path}", flush=True)
    print(f"OCR: Output path: {output_file_path}", flush=True)
    
    # Validate image file exists
    print("OCR: Validating image file exists...", flush=True)
    if not os.path.exists(image_path):
        error_msg = json.dumps({"error": f"Image file not found: {image_path}"})
        print(error_msg, file=sys.stderr)
        sys.exit(1)
    
    print("OCR: Image file found", flush=True)
    
    try:
        print("OCR: Opening image with PIL...", flush=True)
        image = Image.open(image_path)
        print(f"OCR: Image opened successfully (size: {image.size}, mode: {image.mode})", flush=True)
        
        # Note: Surya OCR models may internally resize images for processing
        # The bounding boxes returned are in the original image coordinate space
        # If Surya resizes internally, it scales the bboxes back to original size
        
        # Initialize predictors (these will download models on first use)
        print("OCR: Initializing FoundationPredictor (may download models on first use)...", flush=True)
        foundation_predictor = FoundationPredictor()
        print("OCR: FoundationPredictor initialized", flush=True)
        
        print("OCR: Initializing DetectionPredictor (may download models on first use)...", flush=True)
        det_predictor = DetectionPredictor()
        print("OCR: DetectionPredictor initialized", flush=True)
        
        print("OCR: Initializing RecognitionPredictor...", flush=True)
        rec_predictor = RecognitionPredictor(foundation_predictor)
        print("OCR: RecognitionPredictor initialized", flush=True)
        
        # Run OCR
        print("OCR: Running OCR on image...", flush=True)
        predictions = rec_predictor(
            [image],
            task_names=[TaskNames.ocr_with_boxes],
            det_predictor=det_predictor,
            math_mode=False  # Disable math mode for faster processing
        )
        print("OCR: OCR processing completed", flush=True)
        
        # Extract text and metadata with bounding box information for sorting
        print("OCR: Extracting text and metadata from predictions...", flush=True)
        print("OCR: Bounding boxes are used to sort text in reading order (top-to-bottom, left-to-right)", flush=True)
        print("OCR: Bounding box format: [x0, y0, x1, y1] where (x0,y0) is top-left and (x1,y1) is bottom-right", flush=True)
        line_data = []  # List of tuples: (y_position, x_position, text, confidence)
        
        # Debug: Check structure of first prediction to understand data format
        if predictions and len(predictions) > 0:
            first_pred = predictions[0]
            if hasattr(first_pred, 'text_lines') and len(first_pred.text_lines) > 0:
                first_line = first_pred.text_lines[0]
                print(f"OCR: Debug - First line attributes: {dir(first_line)}", flush=True)
                if hasattr(first_line, 'bbox'):
                    print(f"OCR: Debug - First line bbox type: {type(first_line.bbox)}, value: {first_line.bbox}", flush=True)
                    if isinstance(first_line.bbox, (list, tuple)) and len(first_line.bbox) >= 4:
                        print(f"OCR: Debug - Bbox coordinates: x0={first_line.bbox[0]}, y0={first_line.bbox[1]}, x1={first_line.bbox[2]}, y1={first_line.bbox[3]}", flush=True)
        
        for page_idx, page_pred in enumerate(predictions):
            # Check if page_pred has detection results with bounding boxes
            # Surya OCR with ocr_with_boxes should have both text_lines and bboxes
            bboxes = None
            if hasattr(page_pred, 'bboxes') and page_pred.bboxes is not None:
                bboxes = page_pred.bboxes
            elif hasattr(page_pred, 'line_bboxes') and page_pred.line_bboxes is not None:
                bboxes = page_pred.line_bboxes
            
            for line_idx, line in enumerate(page_pred.text_lines):
                if line.text and line.text.strip():
                    text = line.text.strip()
                    confidence = None
                    
                    # Extract confidence scores if available
                    if hasattr(line, 'confidence') and line.confidence is not None:
                        confidence = line.confidence
                    
                    # Extract bounding box position for sorting
                    y_position = 0
                    x_position = 0
                    bbox_found = False
                    
                    # Try multiple ways to get bounding box
                    # Method 1: Direct bbox attribute on line
                    if hasattr(line, 'bbox') and line.bbox is not None:
                        bbox = line.bbox
                        if isinstance(bbox, (list, tuple)) and len(bbox) >= 4:
                            # bbox format: [x0, y0, x1, y1] or similar
                            x_position = float(bbox[0])
                            y_position = float(bbox[1])
                            bbox_found = True
                            print(f"OCR: Debug - Line {line_idx} bbox from line.bbox: {bbox}", flush=True)
                    
                    # Method 2: From page_pred bboxes array (if available)
                    if not bbox_found and bboxes is not None and line_idx < len(bboxes):
                        bbox = bboxes[line_idx]
                        if isinstance(bbox, (list, tuple)) and len(bbox) >= 4:
                            x_position = float(bbox[0])
                            y_position = float(bbox[1])
                            bbox_found = True
                            print(f"OCR: Debug - Line {line_idx} bbox from page_pred.bboxes: {bbox}", flush=True)
                    
                    # Method 3: Check for geometry or polygon attributes
                    if not bbox_found:
                        if hasattr(line, 'geometry') and line.geometry is not None:
                            geometry = line.geometry
                            if hasattr(geometry, 'bbox'):
                                bbox = geometry.bbox
                                if isinstance(bbox, (list, tuple)) and len(bbox) >= 4:
                                    x_position = float(bbox[0])
                                    y_position = float(bbox[1])
                                    bbox_found = True
                        elif hasattr(line, 'polygon') and line.polygon is not None:
                            # Polygon might be list of points, use first point
                            polygon = line.polygon
                            if isinstance(polygon, (list, tuple)) and len(polygon) > 0:
                                first_point = polygon[0]
                                if isinstance(first_point, (list, tuple)) and len(first_point) >= 2:
                                    x_position = float(first_point[0])
                                    y_position = float(first_point[1])
                                    bbox_found = True
                    
                    if not bbox_found:
                        # Safely handle text that may contain Unicode characters
                        try:
                            text_preview = text[:50].encode('ascii', errors='replace').decode('ascii')
                            print(f"OCR: Warning - No bounding box found for line {line_idx}: '{text_preview}'", flush=True)
                        except Exception:
                            print(f"OCR: Warning - No bounding box found for line {line_idx}: [text contains non-ASCII characters, length={len(text)}]", flush=True)
                    
                    line_data.append((y_position, x_position, text, confidence))
        
        print(f"OCR: Extracted {len(line_data)} lines of text before sorting", flush=True)
        
        # Sort lines by position: top-to-bottom (y_position), then left-to-right (x_position)
        # Use a tolerance for Y positions to group lines that are roughly on the same row
        # Adaptive tolerance: calculate based on image height if we have valid bboxes
        # TODO: Allow bounding box configuration to be passed as argument or via config JSON/YAML
        #   This would enable game-specific handlers to customize:
        #   - Y_TOLERANCE for line grouping
        #   - Bounding box extraction methods
        #   - Region of interest (ROI) definitions for specific UI elements
        #   - Custom sorting algorithms for game-specific layouts
        Y_TOLERANCE = 10  # Default: pixels - lines within this Y distance are considered same row
        
        # If we have valid bounding boxes, calculate adaptive tolerance
        valid_y_positions = [y for y, _, _, _ in line_data if y > 0]
        if valid_y_positions and len(valid_y_positions) > 1:
            # Use 2% of image height or minimum line spacing, whichever is larger
            y_range = max(valid_y_positions) - min(valid_y_positions)
            adaptive_tolerance = max(10, y_range / 50)  # At least 10px, or 2% of range
            Y_TOLERANCE = adaptive_tolerance
            print(f"OCR: Using adaptive Y tolerance: {Y_TOLERANCE:.1f} pixels", flush=True)
        else:
            print(f"OCR: Using default Y tolerance: {Y_TOLERANCE} pixels", flush=True)
        
        def sort_key(item):
            y_pos, x_pos, text, conf = item
            # Round Y position to nearest tolerance value to group similar rows
            # This helps sort by row first, then by column within each row
            # If y_pos is 0 (no bbox found), use a large number to push to end
            if y_pos == 0 and x_pos == 0:
                # No position info - keep original order by using index
                return (999999, 999999)
            y_group = round(y_pos / Y_TOLERANCE) * Y_TOLERANCE
            return (y_group, x_pos)
        
        line_data.sort(key=sort_key)
        print(f"OCR: Sorted {len(line_data)} lines by visual reading order", flush=True)
        
        # Debug: Print first few sorted lines with their positions
        if len(line_data) > 0:
            print("OCR: First 5 sorted lines (y, x, text):", flush=True)
            for i, (y, x, text, conf) in enumerate(line_data[:5]):
                # Safely handle text that may contain Unicode characters
                try:
                    # Truncate and encode safely
                    text_preview = text[:40]
                    # Replace any problematic characters for display
                    safe_text = text_preview.encode('ascii', errors='replace').decode('ascii')
                    print(f"OCR:   [{i}] y={y:.1f}, x={x:.1f}, text='{safe_text}'", flush=True)
                except Exception as e:
                    # If encoding still fails, just print position info
                    print(f"OCR:   [{i}] y={y:.1f}, x={x:.1f}, text=[contains non-ASCII characters, length={len(text)}]", flush=True)
        
        # Extract sorted text and confidence scores
        text_lines = [text for _, _, text, _ in line_data]
        confidence_scores = [conf for _, _, _, conf in line_data if conf is not None]
        line_count = len(text_lines)
        
        # Build response object
        response = {
            "text": "\n".join(text_lines) if text_lines else "",
            "text_lines": text_lines,
            "line_count": line_count,
            "has_text": len(text_lines) > 0
        }
        
        # Add confidence scores if available
        if confidence_scores:
            response["confidence_scores"] = confidence_scores
            response["avg_confidence"] = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0.0
        
        # Write JSON to output file
        print(f"OCR: Writing results to output file: {output_file_path}", flush=True)
        with open(output_file_path, 'w', encoding='utf-8') as f:
            json.dump(response, f, ensure_ascii=False)
        
        print("OCR: Successfully completed OCR processing", flush=True)
            
    except Exception as e:
        print(f"OCR: Error occurred: {str(e)}", file=sys.stderr, flush=True)
        import traceback
        print(f"OCR: Traceback: {traceback.format_exc()}", file=sys.stderr, flush=True)
        
        # Write error to output file as well
        error_response = {"error": f"Error processing image: {str(e)}"}
        try:
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(error_response, f, ensure_ascii=False)
        except:
            # If we can't write the error file, at least print it
            print(json.dumps(error_response), file=sys.stderr, flush=True)
        sys.exit(1)

