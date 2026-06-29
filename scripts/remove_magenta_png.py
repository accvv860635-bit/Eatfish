import struct
import sys
import zlib


PNG_SIG = b"\x89PNG\r\n\x1a\n"


def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path):
    with open(path, "rb") as f:
        if f.read(8) != PNG_SIG:
            raise ValueError("not a PNG")

        width = height = bit_depth = color_type = None
        idat = []
        while True:
            length_data = f.read(4)
            if not length_data:
                break
            length = struct.unpack(">I", length_data)[0]
            chunk_type = f.read(4)
            data = f.read(length)
            f.read(4)
            if chunk_type == b"IHDR":
                width, height, bit_depth, color_type, _, _, _ = struct.unpack(
                    ">IIBBBBB", data
                )
            elif chunk_type == b"IDAT":
                idat.append(data)
            elif chunk_type == b"IEND":
                break

    if bit_depth != 8 or color_type != 2:
        raise ValueError("expected 8-bit RGB PNG")

    raw = zlib.decompress(b"".join(idat))
    stride = width * 3
    rows = []
    src = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[src]
        src += 1
        row = bytearray(raw[src : src + stride])
        src += stride
        for i in range(stride):
            left = row[i - 3] if i >= 3 else 0
            up = previous[i]
            up_left = previous[i - 3] if i >= 3 else 0
            if filter_type == 1:
                row[i] = (row[i] + left) & 255
            elif filter_type == 2:
                row[i] = (row[i] + up) & 255
            elif filter_type == 3:
                row[i] = (row[i] + ((left + up) >> 1)) & 255
            elif filter_type == 4:
                row[i] = (row[i] + paeth(left, up, up_left)) & 255
            elif filter_type != 0:
                raise ValueError(f"unsupported PNG filter {filter_type}")
        rows.append(row)
        previous = row
    return width, height, rows


def png_chunk(chunk_type, data):
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def write_rgba_png(path, width, height, rows):
    scanlines = bytearray()
    for row in rows:
        scanlines.append(0)
        scanlines.extend(row)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(PNG_SIG)
        f.write(png_chunk(b"IHDR", ihdr))
        f.write(png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 9)))
        f.write(png_chunk(b"IEND", b""))


def convert(input_path, output_path):
    width, height, rgb_rows = read_png(input_path)
    rgba_rows = []
    for row in rgb_rows:
        out = bytearray()
        for i in range(0, len(row), 3):
            r, g, b = row[i], row[i + 1], row[i + 2]
            distance = abs(r - 255) + abs(g - 0) + abs(b - 255)
            alpha = 0 if distance < 80 else 255
            if alpha == 0:
                r = g = b = 0
            out.extend((r, g, b, alpha))
        rgba_rows.append(out)
    write_rgba_png(output_path, width, height, rgba_rows)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: remove_magenta_png.py input.png output.png")
    convert(sys.argv[1], sys.argv[2])
