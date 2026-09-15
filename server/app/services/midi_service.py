TPQ = 480


def varlen(value):
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.append(0x80 | (value & 0x7F))
        value >>= 7
    return bytes(reversed(out))


def read_varlen(data, pos):
    value = 0
    n = len(data)
    while pos < n:
        b = data[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not b & 0x80:
            return value, pos
    return value, pos


def write_midi(notes, bpm):
    mpq = int(round(60000000.0 / bpm)) if bpm > 0 else 500000
    if mpq <= 0:
        mpq = 500000
    events = [(0, b"\xFF\x51\x03" + mpq.to_bytes(3, "big"))]
    for nt in notes:
        on = int(round(nt["start"] * bpm / 60.0 * TPQ)) if bpm > 0 else 0
        off = int(round(nt["end"] * bpm / 60.0 * TPQ)) if bpm > 0 else 0
        if off <= on:
            off = on + 1
        vel = nt.get("velocity", 80)
        pitch = max(0, min(127, int(nt["midi"])))
        events.append((on, bytes([0x90, pitch, vel & 0x7F])))
        events.append((off, bytes([0x80, pitch, 64])))
    events.append((max([t for t, _ in events] + [0]) + 1, b"\xFF\x2F\x00"))
    events.sort(key=lambda x: x[0])
    track = b""
    last = 0
    for tick, msg in events:
        track += varlen(tick - last) + msg
        last = tick
    head = b"MThd" + (6).to_bytes(4, "big") + (0).to_bytes(2, "big") + (1).to_bytes(2, "big") + TPQ.to_bytes(2, "big")
    return head + b"MTrk" + len(track).to_bytes(4, "big") + track


def read_midi(data):
    if len(data) < 14 or data[0:4] != b"MThd":
        raise ValueError("bad header")
    ntrks = int.from_bytes(data[10:12], "big")
    div = int.from_bytes(data[12:14], "big")
    if div <= 0:
        raise ValueError("bad division")
    pos = 14
    notes = []
    for _ in range(ntrks):
        if data[pos:pos + 4] != b"MTrk":
            raise ValueError("bad track")
        tlen = int.from_bytes(data[pos + 4:pos + 8], "big")
        end = min(pos + 8 + tlen, len(data))
        pos += 8
        tick = 0
        status = 0
        sounding = {}
        while pos < end:
            delta, pos = read_varlen(data, pos)
            tick += delta
            if pos >= end:
                break
            b = data[pos]
            if b & 0x80:
                status = b
                pos += 1
            if status == 0xFF:
                if pos >= end:
                    break
                pos += 1
                ln, pos = read_varlen(data, pos)
                pos += ln
                status = 0
            elif (status & 0xF0) == 0x90 or (status & 0xF0) == 0x80:
                if pos + 1 >= end:
                    break
                pitch = data[pos]
                vel = data[pos + 1]
                pos += 2
                if (status & 0xF0) == 0x90 and vel > 0:
                    sounding[pitch] = tick
                else:
                    if pitch in sounding:
                        t0 = sounding.pop(pitch)
                        notes.append({"midi": pitch, "start_beat": round(t0 / div, 3), "dur_beat": round((tick - t0) / div, 3)})
            elif status == 0xF0 or status == 0xF7:
                ln, pos = read_varlen(data, pos)
                pos += ln
                status = 0
            elif (status & 0xF0) == 0xF0:
                if status in (0xF1, 0xF3):
                    pos += 1
                elif status == 0xF2:
                    pos += 2
            elif (status & 0xF0) in (0xC0, 0xD0):
                pos += 1
            else:
                pos += 2
    notes.sort(key=lambda x: x["start_beat"])
    return notes
