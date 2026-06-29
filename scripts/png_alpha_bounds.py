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

    if bit_depth != 8 or color_type != 6:
        raise ValueError("expected 8-bit RGBA PNG")

    raw = zlib.decompress(b"".join(idat))
    channels = 4
    stride = width * channels
    rows = []
    src = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[src]
        src += 1
        row = bytearray(raw[src : src + stride])
        src += stride
        for i in range(stride):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            up_left = previous[i - channels] if i >= channels else 0
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


def bounds_for_cell(rows, x0, y0, width, height):
    min_x, min_y = width, height
    max_x, max_y = -1, -1
    for y in range(y0, y0 + height):
        row = rows[y]
        for x in range(x0, x0 + width):
            alpha = row[x * 4 + 3]
            if alpha > 16:
                local_x = x - x0
                local_y = y - y0
                min_x = min(min_x, local_x)
                min_y = min(min_y, local_y)
                max_x = max(max_x, local_x)
                max_y = max(max_y, local_y)
    if max_x < 0:
        return (0, 0, width, height)
    pad = 4
    min_x = max(0, min_x - pad)
    min_y = max(0, min_y - pad)
    max_x = min(width - 1, max_x + pad)
    max_y = min(height - 1, max_y + pad)
    return (min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


if __name__ == "__main__":
    image_path = sys.argv[1]
    columns = int(sys.argv[2])
    rows_count = int(sys.argv[3])
    width, height, rows = read_png(image_path)
    cell_w = width // columns
    cell_h = height // rows_count
    for index in range(columns * rows_count):
        col = index % columns
        row = index // columns
        x, y, w, h = bounds_for_cell(rows, col * cell_w, row * cell_h, cell_w, cell_h)
        print(f"Rect.fromLTWH({col * cell_w + x}.0, {row * cell_h + y}.0, {w}.0, {h}.0),")
