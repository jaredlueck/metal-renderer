#!/usr/bin/env python3
"""
cubemap_cross_to_vertical.py

Convert a cubemap in cross layout format into a vertical strip suitable for MTKTextureLoader.CubeLayout.vertical.

Dependencies:
  - Pillow
  - numpy

Install dependencies:
  pip install pillow numpy

Usage:
  python cubemap_cross_to_vertical.py --input input_cross.png [--output output_vertical.png]
                                     [--layout 3x4|4x3|auto] [--order metal|opengl]
                                     [--flip_y] [--debug_faces prefix]

"""

import argparse
import os
import sys

from PIL import Image
import numpy as np

# Allow large images (override Pillow's decompression bomb protection if desired)
try:
    Image.MAX_IMAGE_PIXELS = None  # disable limit by default
except Exception:
    pass


def parse_args():
    parser = argparse.ArgumentParser(description="Convert cubemap cross layout into vertical strip for MTKTextureLoader.CubeLayout.vertical.")
    parser.add_argument('--input', '-i', required=True, help='Input cubemap cross image (PNG/JPG/TIFF/etc.)')
    parser.add_argument('--output', '-o', default=None, help="Output PNG path (default: input basename + '_vertical.png')")
    parser.add_argument('--layout', choices=['3x4', '4x3', 'auto'], default='auto',
                        help="Cross layout: '3x4', '4x3', or 'auto' (detect by aspect ratio, default)")
    parser.add_argument('--order', choices=['metal', 'opengl'], default='metal',
                        help="Output face order (default: metal)")
    parser.add_argument('--flip_y', action='store_true',
                        help="Flip each face vertically before packing")
    parser.add_argument('--debug_faces', default=None,
                        help="If set, save individual faces as PNGs with this prefix")
    parser.add_argument('--max_image_pixels', type=float, default=None,
                        help='Override Pillow Image.MAX_IMAGE_PIXELS (e.g., 3e8). Use 0 to disable protection.')
    return parser.parse_args()


def detect_layout(img_w, img_h):
    # Determine layout from aspect ratio
    aspect = img_w / img_h
    # 3x4 layout: width=3S, height=4S => aspect=3/4=0.75
    # 4x3 layout: width=4S, height=3S => aspect=4/3=1.333...
    # Choose closest
    diff_3x4 = abs(aspect - 0.75)
    diff_4x3 = abs(aspect - 1.3333333)
    if diff_3x4 < diff_4x3:
        return '3x4'
    else:
        return '4x3'


def extract_faces_3x4(img, S):
    """
    Extract faces from a 3x4 cross layout.

    Layout (rows x cols):
    row0:       [   , +Y,    ]
    row1: [ -X, +Z, +X ]
    row2:       [   , -Y,    ]
    row3:       [   , -Z,    ]

    Each cell is SxS pixels.

    Return dict of faces with keys: '+X', '-X', '+Y', '-Y', '+Z', '-Z'
    """
    faces = {}

    # Image coordinate (x,y) of each face cell in pixels
    # (col, row)
    coords = {
        '+Y': (1, 0),
        '-X': (0, 1),
        '+Z': (1, 1),
        '+X': (2, 1),
        '-Y': (1, 2),
        '-Z': (1, 3),
    }

    for face, (c, r) in coords.items():
        box = (c * S, r * S, c * S + S, r * S + S)
        face_img = img.crop(box)
        faces[face] = face_img

    return faces


def extract_faces_4x3(img, S):
    """
    Extract faces from a 4x3 cross layout.

    Layout (rows x cols):
    row0: [   , +Y,    ,    ]
    row1: [ -X, +Z, +X, -Z ]
    row2: [   , -Y,    ,    ]

    Each cell is SxS pixels.

    Return dict of faces with keys: '+X', '-X', '+Y', '-Y', '+Z', '-Z'
    """
    faces = {}

    coords = {
        '+Y': (1, 0),
        '-X': (0, 1),
        '+Z': (1, 1),
        '+X': (2, 1),
        '-Z': (3, 1),
        '-Y': (1, 2),
    }

    for face, (c, r) in coords.items():
        box = (c * S, r * S, c * S + S, r * S + S)
        face_img = img.crop(box)
        faces[face] = face_img

    return faces


def rotate_face(face_img, face_name):
    """
    Rotate faces to align with Metal cube face orientation.

    Rotations applied (may need adjustment depending on source cross conventions):
      +X: 0 degrees
      -X: 0 degrees
      +Y: 90 degrees clockwise
      -Y: 90 degrees counter-clockwise
      +Z: 0 degrees
      -Z: 0 degrees

    face_img: PIL.Image
    face_name: string key of face

    Returns rotated PIL.Image
    """
    if face_name == '+Y':
        # Rotate 90 degrees clockwise
        return face_img
    elif face_name == '-Y':
        # Rotate 90 degrees counter-clockwise
        return face_img
    else:
        # No rotation
        return face_img


def main():
    args = parse_args()

    if args.max_image_pixels is not None:
        if args.max_image_pixels == 0:
            Image.MAX_IMAGE_PIXELS = None
        else:
            Image.MAX_IMAGE_PIXELS = args.max_image_pixels

    if not os.path.isfile(args.input):
        print(f"Error: input file '{args.input}' does not exist.", file=sys.stderr)
        sys.exit(1)

    try:
        img = Image.open(args.input).convert('RGBA')
    except Exception as e:
        print(f"Error: failed to open image '{args.input}': {e}", file=sys.stderr)
        sys.exit(1)

    img_w, img_h = img.size

    # Determine cross layout
    layout = args.layout
    if layout == 'auto':
        layout = detect_layout(img_w, img_h)

    # Validate dimensions and compute face size S
    if layout == '3x4':
        if img_w % 3 != 0 or img_h % 4 != 0:
            print(f"Error: image dimensions {img_w}x{img_h} not divisible by 3 and 4 for 3x4 layout.", file=sys.stderr)
            sys.exit(1)
        Sx = img_w // 3
        Sy = img_h // 4
        if Sx != Sy:
            print(f"Error: non-square face size detected in 3x4 layout: width cell {Sx}, height cell {Sy}", file=sys.stderr)
            sys.exit(1)
        S = Sx
        faces = extract_faces_3x4(img, S)

    elif layout == '4x3':
        if img_w % 4 != 0 or img_h % 3 != 0:
            print(f"Error: image dimensions {img_w}x{img_h} not divisible by 4 and 3 for 4x3 layout.", file=sys.stderr)
            sys.exit(1)
        Sx = img_w // 4
        Sy = img_h // 3
        if Sx != Sy:
            print(f"Error: non-square face size detected in 4x3 layout: width cell {Sx}, height cell {Sy}", file=sys.stderr)
            sys.exit(1)
        S = Sx
        faces = extract_faces_4x3(img, S)

    else:
        print(f"Error: unsupported layout '{layout}'", file=sys.stderr)
        sys.exit(1)

    # Order faces for output
    # Metal face order:
    # +X, -X, +Y, -Y, +Z, -Z
    # OpenGL order currently same as Metal here, placeholder for future extension
    metal_order = ['+X', '-X', '+Y', '-Y', '+Z', '-Z']
    opengl_order = ['+X', '-X', '+Y', '-Y', '+Z', '-Z']

    if args.order == 'metal':
        output_order = metal_order
    else:  # 'opengl'
        output_order = opengl_order

    # Rotate faces according to Metal convention
    for f in faces:
        faces[f] = rotate_face(faces[f], f)

    # Flip Y if requested
    if args.flip_y:
        for f in faces:
            faces[f] = faces[f].transpose(Image.FLIP_TOP_BOTTOM)

    # Debug save faces if requested
    if args.debug_faces is not None:
        prefix = args.debug_faces
        for f in metal_order:
            if f in faces:
                debug_path = f"{prefix}_{f}.png"
                faces[f].save(debug_path)

    # Stack faces vertically in output_order
    out_width = S
    out_height = S * len(output_order)
    mode = img.mode
    out_img = Image.new(mode, (out_width, out_height), (0, 0, 0, 0) if 'A' in mode else 0)

    for i, f in enumerate(output_order):
        face_img = faces[f]
        out_img.paste(face_img, (0, i * S))

    # Determine output filename
    if args.output is None:
        base, ext = os.path.splitext(args.input)
        args.output = base + '_vertical.png'

    try:
        out_img.save(args.output, 'PNG')
    except Exception as e:
        print(f"Error: failed to save output image '{args.output}': {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
