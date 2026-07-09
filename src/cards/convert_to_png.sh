#!/bin/sh
# Converts all card SVGs in static/cards/ to 1024px-high PNGs using Inkscape.
# Run from the project root: sh static/cards/convert_to_png.sh
set -e

for svg in src/cards/original/*.svg; do
    png="src/cards/${svg##*/}"
    png="${png%.svg}.png"
    echo "$svg -> $png"
    inkscape -h 1024 "$svg" -o "$png"
done
