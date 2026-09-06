#!/usr/bin/python3
"""PH315-52 bridge using cleyton1986/predator-sense's RGB/WMI protocols."""
import json
import os
from pathlib import Path
import re
import sys

DYNAMIC = Path('/dev/acer-gkbbl-0')
STATIC = Path('/dev/acer-gkbbl-static-0')
HWMON = Path('/sys/class/hwmon')
STATE = Path('/var/lib/omarchy-predatorsense-ph31552/facer-keyboard.json')

def number(value, low, high):
    if not re.fullmatch(r'[0-9]+', str(value)):
        raise ValueError('Invalid number')
    value = int(value)
    if not low <= value <= high:
        raise ValueError('Value outside supported range')
    return value

def rgb(value):
    if not re.fullmatch(r'[0-9a-fA-F]{6}', value):
        raise ValueError('Invalid RGB color')
    return bytes.fromhex(value)

def effect_payload(mode, speed, brightness, direction, color):
    mode = number(mode, 0, 5)
    payload = bytearray(16)
    payload[:8] = bytes([mode, number(speed, 0, 9), number(brightness, 0, 100),
                         8 if mode == 3 else 0, number(direction, 1, 2)]) + rgb(color)
    payload[9] = 1
    return bytes(payload)

def zone_payloads(color):
    return [bytes([zone]) + rgb(color) for zone in (1, 2, 4, 8)]

def set_fan(mode):
    if mode not in ('auto', '50', '70', '100'):
        raise ValueError('Unsupported fan preset')
    hwmon = next((d for d in HWMON.glob('hwmon*')
                  if 'acer' in (d / 'name').read_text() and (d / 'pwm1_enable').exists()), None)
    if hwmon is None:
        raise OSError('Acer WMI fan control is unavailable')
    controls = [hwmon / f'pwm{n}_enable' for n in (1, 2)]
    speeds = [hwmon / f'pwm{n}' for n in (1, 2)]
    previous = [p.read_text().strip() for p in controls]
    previous_speeds = [p.read_text().strip() if mode_value == '1' else None
                       for p, mode_value in zip(speeds, previous)]
    target = '2' if mode == 'auto' else '0' if mode == '100' else '1'
    try:
        for p in controls:
            p.write_text(target)
        if target == '1':
            for p in speeds:
                p.write_text(str(int(mode) * 255 // 100))
        if any(p.read_text().strip() != target for p in controls):
            raise OSError('Firmware did not accept the fan mode')
    except Exception:
        for control, speed, mode_value, speed_value in zip(controls, speeds, previous, previous_speeds):
            control.write_text(mode_value)
            if speed_value is not None:
                speed.write_text(speed_value)
        raise


def write_device(path, payload):
    with path.open('wb', buffering=0) as stream:
        if stream.write(payload) != len(payload):
            raise OSError('Incomplete device write')

def apply_keyboard(state):
    if state['mode'] == '0':
        commit = effect_payload('0', '0', state['brightness'], '1', '000000')
        for payload in zone_payloads(state['color']):
            write_device(STATIC, payload)
            write_device(DYNAMIC, commit)
    else:
        write_device(DYNAMIC, effect_payload(state['mode'], state['speed'],
                     state['brightness'], state['direction'], state['color']))
    STATE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state) + '\n')

def main(args):
    if os.geteuid() != 0:
        raise PermissionError('Administrator privileges required')
    if Path('/sys/class/dmi/id/product_name').read_text().strip() != 'Predator PH315-52':
        raise ValueError('This bridge is restricted to Predator PH315-52')
    verb, *values = args
    if verb == 'fan' and len(values) == 1:
        set_fan(values[0])
        return
    if verb == 'kb-zone' and len(values) == 2:
        color, brightness = values
        rgb(color)
        state = dict(mode='0', speed='0', brightness=str(number(brightness, 0, 100)), direction='1', color=color)
    elif verb == 'kb-effect' and len(values) == 5:
        effect_payload(*values)
        state = dict(zip(('mode', 'speed', 'brightness', 'direction', 'color'), values))
    elif verb == 'kb-bright' and len(values) == 1:
        brightness = str(number(values[0], 0, 100))
        try:
            state = json.loads(STATE.read_text())
        except FileNotFoundError:
            state = dict(mode='0', speed='0', brightness='100', direction='1', color='ffffff')
        state['brightness'] = brightness
    else:
        raise ValueError('Unsupported command or argument count')
    apply_keyboard(state)

if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, KeyError) as error:
        print(f'PredatorSense: {error}', file=sys.stderr)
        sys.exit(1)
