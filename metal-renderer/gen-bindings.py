#!/usr/bin/env python3
"""
Generate Bindings.h from Bindings.swift

Usage:
  python3 gen-bindings.py [path/to/Bindings.swift]

Parses lines like:
  enum Bindings {
      static let vertexBuffer = 0
      ...
  }

Outputs a header with:
  typedef enum Bindings : unsigned int {
      BindingsVertexBuffer = 0,
      ...
  } Bindings;

No Foundation dependency.
"""
import sys
import os
import re
from pathlib import Path

LET_RE = re.compile(r"^\s*static\s+let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([0-9]+)\s*$")
ENUM_START_RE = re.compile(r"^\s*enum\s+Bindings\s*\{\s*$")

class Die(Exception):
    pass

def to_pascal_case(name: str) -> str:
    if '_' in name:
        parts = name.split('_')
    else:
        # split camelCase
        parts = []
        current = ''
        for ch in name:
            if ch.isupper():
                if current:
                    parts.append(current)
                current = ch
            else:
                current += ch
        if current:
            parts.append(current)
    return ''.join(p[:1].upper() + p[1:] for p in parts if p)

def parse_bindings(source: str):
    lines = source.splitlines()
    inside_enum = False
    brace_depth = 0
    entries = []

    for line in lines:
        if not inside_enum:
            if ENUM_START_RE.match(line):
                inside_enum = True
                brace_depth = 1
            continue
        for ch in line:
            if ch == '{':
                brace_depth += 1
            elif ch == '}':
                brace_depth -= 1
        if brace_depth == 0:
            inside_enum = False
            continue
        m = LET_RE.match(line)
        if m:
            name, value = m.group(1), m.group(2)
            entries.append((name, value))
    return entries

def generate_header(entries, input_name: str) -> str:
    guard_name = "BINDINGS_H_GENERATED"
    lines = []
    lines.append(f"// This file is generated from {input_name}. Do not edit manually.")
    lines.append(f"#ifndef {guard_name}")
    lines.append(f"#define {guard_name}")
    lines.append("")
    lines.append("typedef enum Bindings : unsigned int {")
    for i, (name, value) in enumerate(entries):
        case_name = "Bindings" + to_pascal_case(name)
        comma = "," if i < len(entries) - 1 else ""
        lines.append(f"    {case_name} = {value}{comma}")
    lines.append("} Bindings;")
    lines.append("")
    lines.append(f"#endif /* {guard_name} */")
    return "\n".join(lines) + "\n"

def main():
    try:
        input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Bindings.swift")
        if not input_path.exists():
            raise Die(f"Could not read {input_path}")
        source = input_path.read_text(encoding='utf-8')
        entries = parse_bindings(source)
        if not entries:
            raise Die(f"No bindings found in enum Bindings in {input_path}. Ensure lines look like `static let name = number`.")
        header = generate_header(entries, input_path.name)
        shaders_dir = input_path.parent / "Shaders"
        shaders_dir.mkdir(parents=True, exist_ok=True)
        output_path = shaders_dir / "Bindings.h"
        output_path.write_text(header, encoding='utf-8')
        print(f"Generated {output_path}")
    except Die as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
