"""Round-trip check for the bit layout used by lib/bitstream.lua + lib/action_parser.lua.

Mirrors the Lua reader in Python, builds a synthetic 0x0028 packet from known field
values, then decodes it with the same sequence the Lua code uses. Run:

    python tools/test_action_parser.py
"""
import math


def read_at(raw, abs_bit, count):
    """Little endian, LSB-first bit read; returns None past the end of the buffer."""
    if count < 0 or count > 32:
        return None
    byte_index = abs_bit // 8
    bit_offset = abs_bit - byte_index * 8
    if byte_index < 0 or count > len(raw) * 8 - abs_bit:
        return None
    span = math.ceil((bit_offset + count) / 8)
    value = 0
    for k in range(span - 1, -1, -1):
        value = value * 256 + raw[byte_index + k]
    value >>= bit_offset
    return value & ((1 << count) - 1) if count else 0


class Writer:
    def __init__(self):
        self.bits = []

    def put(self, value, count):
        for i in range(count):
            self.bits.append((value >> i) & 1)

    def bytes(self, pad_to=0):
        while len(self.bits) % 8 != 0 or len(self.bits) < pad_to * 8:
            self.bits.append(0)
        out = bytearray()
        for i in range(0, len(self.bits), 8):
            byte = 0
            for j in range(8):
                byte |= self.bits[i + j] << j
            out.append(byte)
        return bytes(out)


def decode(raw):
    """Replicates action_parser.parse()."""
    state = {'bit': 40}

    def take(count):
        value = read_at(raw, state['bit'], count)
        if value is None:
            raise IndexError('buffer overrun')
        state['bit'] += count
        return value

    action = {}
    action['actor_id'] = take(32)
    action['target_count'] = take(10)
    action['category'] = take(4)
    action['param'] = take(16)
    action['_unknown1'] = take(16)
    action['recast'] = take(32)
    targets = []
    for _ in range(action['target_count']):
        target = {'id': take(32), 'action_count': take(4), 'actions': []}
        for _ in range(target['action_count']):
            entry = {}
            for name, width in (('reaction', 5), ('animation', 12), ('effect', 4),
                                ('stagger', 3), ('knockback', 3), ('param', 17),
                                ('message', 10), ('_unknown', 31)):
                entry[name] = take(width)
            if take(1):
                entry['has_add_effect'] = True
                for name, width in (('add_effect_animation', 6), ('add_effect_effect', 4),
                                    ('add_effect_param', 17), ('add_effect_message', 10)):
                    entry[name] = take(width)
            else:
                entry['has_add_effect'] = False
            if take(1):
                entry['has_spike_effect'] = True
                for name, width in (('spike_effect_animation', 6), ('spike_effect_effect', 4),
                                    ('spike_effect_param', 14), ('spike_effect_message', 10)):
                    entry[name] = take(width)
            else:
                entry['has_spike_effect'] = False
            target['actions'].append(entry)
        targets.append(target)
    action['targets'] = targets
    action['_end_bit'] = state['bit']
    return action


def build(actor_id, target_count, category, param, recast, targets):
    w = Writer()
    w.put(0, 40)                       # header + size byte
    w.put(actor_id, 32)
    w.put(target_count, 10)
    w.put(category, 4)
    w.put(param, 16)
    w.put(0, 16)                       # _unknown1
    w.put(recast, 32)
    for target in targets:
        w.put(target['id'], 32)
        w.put(len(target['actions']), 4)
        for entry in target['actions']:
            w.put(entry['reaction'], 5)
            w.put(entry['animation'], 12)
            w.put(entry['effect'], 4)
            w.put(entry['stagger'], 3)
            w.put(entry['knockback'], 3)
            w.put(entry['param'], 17)
            w.put(entry['message'], 10)
            w.put(entry.get('_unknown', 0), 31)
            has_add = 1 if entry.get('has_add_effect') else 0
            w.put(has_add, 1)
            if has_add:
                w.put(entry['add_effect_animation'], 6)
                w.put(entry['add_effect_effect'], 4)
                w.put(entry['add_effect_param'], 17)
                w.put(entry['add_effect_message'], 10)
            has_spike = 1 if entry.get('has_spike_effect') else 0
            w.put(has_spike, 1)
            if has_spike:
                w.put(entry['spike_effect_animation'], 6)
                w.put(entry['spike_effect_effect'], 4)
                w.put(entry['spike_effect_param'], 14)
                w.put(entry['spike_effect_message'], 10)
    return w.bytes()


def main():
    failures = []

    # 1. Sanity: a 32 bit field at bit 40 is exactly the little endian dword at 0x05.
    raw = bytearray(64)
    for i, b in enumerate([0x11, 0x22, 0x33, 0x44]):
        raw[5 + i] = b
    expected = 0x44332211
    got = read_at(bytes(raw), 40, 32)
    if got != expected:
        failures.append('bit 40 32-bit read: got %#x want %#x' % (got, expected))

    # 2. Unaligned read across a byte boundary (Param 16 @ bit 86).
    w = Writer()
    w.put(0, 86)
    w.put(0x1234, 16)
    got = read_at(w.bytes(), 86, 16)
    if got != 0x1234:
        failures.append('bit 86 16-bit read: got %#x want %#x' % (got, 0x1234))

    # 2b. Straddling the tail of the buffer must refuse rather than misread.
    w = Writer()
    w.put(0, 86)
    if read_at(w.bytes(), 86, 16) is not None:
        failures.append('read past end did not return None')

    # 3. Full round trip: melee swing with an added effect and a spike effect.
    entry = {
        'reaction': 8, 'animation': 0, 'effect': 2, 'stagger': 0, 'knockback': 0,
        'param': 137, 'message': 1, '_unknown': 0,
        'has_add_effect': True, 'add_effect_animation': 23, 'add_effect_effect': 1,
        'add_effect_param': 119, 'add_effect_message': 230,
        'has_spike_effect': True, 'spike_effect_animation': 1, 'spike_effect_effect': 2,
        'spike_effect_param': 3, 'spike_effect_message': 186,
    }
    second = dict(entry)
    second.update(has_spike_effect=False, add_effect_animation=0)
    for key in ('spike_effect_animation', 'spike_effect_effect', 'spike_effect_param',
                'spike_effect_message'):
        second.pop(key, None)
    targets = [{'id': 0x10000401, 'actions': [entry]},
               {'id': 0x40000002, 'actions': [entry, second]}]
    raw = build(0x40000001, 2, 1, 0, 0, targets)
    act = decode(raw)

    checks = [
        (act['actor_id'], 0x40000001, 'actor_id'),
        (act['target_count'], 2, 'target_count'),
        (act['category'], 1, 'category'),
        (len(act['targets']), 2, 'targets length'),
        (act['targets'][0]['id'], 0x10000401, 'target 1 id'),
        (act['targets'][1]['action_count'], 2, 'target 2 action count'),
        (act['targets'][0]['actions'][0]['reaction'], 8, 'reaction'),
        (act['targets'][0]['actions'][0]['add_effect_animation'], 23, 'add_effect_animation'),
        (act['targets'][0]['actions'][0]['add_effect_param'], 119, 'add_effect_param'),
        (act['targets'][0]['actions'][0]['spike_effect_message'], 186, 'spike_effect_message'),
        (act['targets'][1]['actions'][1]['has_spike_effect'], False, 'absent spike group'),
        (act['targets'][1]['actions'][1].get('spike_effect_param'), None, 'absent spike field'),
        (act['targets'][1]['actions'][1]['param'], 137, 'second action param'),
    ]
    for got, want, label in checks:
        if got != want:
            failures.append('%s: got %r want %r' % (label, got, want))

    # 4. Truncated packet must fail cleanly instead of returning garbage.
    try:
        decode(raw[:12])
        failures.append('truncated packet decoded without error')
    except IndexError:
        pass

    if failures:
        print('FAIL')
        for f in failures:
            print(' -', f)
        return 1
    print('OK: bit layout round trips (%d bit packet, decode ends at bit %d)'
          % (len(raw), act['_end_bit']))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
