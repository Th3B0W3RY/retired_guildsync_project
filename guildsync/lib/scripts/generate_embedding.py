#!/usr/bin/env python3
import sys
import os
import json
from sentence_transformers import SentenceTransformer
from PIL import Image

if __name__ == "__main__":
    if len(sys.argv) < 3:
        error_msg = json.dumps({"error": "Usage: generate_embedding.py <image_path> <output_file_path>"})
        print(error_msg, file=sys.stderr)
        sys.exit(1)
    
    image_path = sys.argv[1]
    output_file_path = sys.argv[2]
    
    # Validate image file exists
    if not os.path.exists(image_path):
        error_msg = json.dumps({"error": f"Image file not found: {image_path}"})
        print(error_msg, file=sys.stderr)
        sys.exit(1)
    
    try:
        # Validate image can be opened
        try:
            image = Image.open(image_path)
            # Verify image is valid
            image.verify()
            # Reopen after verify (verify closes the file)
            image = Image.open(image_path)
        except Exception as img_error:
            error_response = {"error": f"Invalid or corrupted image file: {str(img_error)}"}
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(error_response, f, ensure_ascii=False)
            sys.exit(1)
        
        # Load model (cache on first run)
        # Uses open-source CLIP model - no API dependency required
        model_name = os.environ.get('EMBEDDING_MODEL', 'clip-ViT-B-32')
        
        try:
            model = SentenceTransformer(model_name)
        except Exception as model_error:
            error_response = {"error": f"Failed to load embedding model '{model_name}': {str(model_error)}"}
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(error_response, f, ensure_ascii=False)
            sys.exit(1)
        
        # Generate embedding
        try:
            embedding = model.encode(image)
            
            # Validate embedding was generated
            if embedding is None or embedding.size == 0:
                error_response = {"error": "Embedding generation returned empty result"}
                with open(output_file_path, 'w', encoding='utf-8') as f:
                    json.dump(error_response, f, ensure_ascii=False)
                sys.exit(1)
            
            embedding_list = embedding.tolist()
            
            # Validate embedding list
            if not embedding_list or len(embedding_list) == 0:
                error_response = {"error": "Embedding list is empty"}
                with open(output_file_path, 'w', encoding='utf-8') as f:
                    json.dump(error_response, f, ensure_ascii=False)
                sys.exit(1)
            
            # Write JSON array to output file
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(embedding_list, f)
                
        except Exception as encode_error:
            error_response = {"error": f"Failed to generate embedding: {str(encode_error)}"}
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(error_response, f, ensure_ascii=False)
            sys.exit(1)
        
    except Exception as e:
        # Write error to output file as well
        error_response = {"error": f"Error generating embedding: {str(e)}"}
        try:
            with open(output_file_path, 'w', encoding='utf-8') as f:
                json.dump(error_response, f, ensure_ascii=False)
        except:
            # If we can't write the error file, at least print it
            print(json.dumps(error_response), file=sys.stderr)
        sys.exit(1)

