# Hero background MP4 (`hero-background.mp4`)

**Date:** 2026-04-04 (encode) · **Playback rev.** 2026-04-05

## Why it was re-encoded

The source clip (~10s, 30fps) **dims toward the end** (frame-averaged luma ~0.29 at t=0 vs ~0.17–0.18 mid–late). Looping back to t=0 produced a **visible jump** (bright restart) and a **dark stretch** before the cut.

## In-file crossfade (FFmpeg)

Blend the **last 1s** with the **first 1s** so encoded **end** matches **start** more closely:

```bash
# L=10s, crossfade d=1s → main 0–9s, head 0–1s, offset=8
ffmpeg -y -i SOURCE.mp4 -filter_complex "
[0:v]trim=start=0:duration=9,setpts=PTS-STARTPTS,format=yuv420p[main];
[0:v]trim=start=0:duration=1,setpts=PTS-STARTPTS,format=yuv420p[head];
[main][head]xfade=transition=fade:duration=1:offset=8,format=yuv420p[v]
" -map "[v]" -an -c:v libx264 -profile:v baseline -level 4.0 -pix_fmt yuv420p -movflags +faststart -brand mp42 hero-background.mp4
```

Output duration **~9s**. Re-check first vs last-frame luma if you replace `SOURCE.mp4`.

## Playback in the app (hybrid — 2026-04-05)

**Native `<video loop>` is not used.** Browsers often **hitch** when rewinding to `currentTime = 0`. GuildSync uses the common **dual `<video>`** pattern (same `src`): **opacity crossfade** before the active clip ends, **`requestAnimationFrame`** refinement near the boundary (coarse `timeupdate` is ~4 Hz), **`requestVideoFrameCallback`** before fading when available, **`playbackRate` 0.75**, and a **vignette at `z-[8]`** so layers never flash above the dimmer.

See `landing_hero_video_controller.js`. Historical encode/playback notes beyond this runtime asset README belong in `guildsync_knowledge_base`.
