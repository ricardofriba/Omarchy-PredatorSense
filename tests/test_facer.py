import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
p=Path(__file__).resolve().parents[1] / 'facer.py'
spec=importlib.util.spec_from_file_location('bridge',p)
b=importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
class Payloads(unittest.TestCase):
    def test_wave_payload(self):
        self.assertEqual(b.effect_payload('3','5','100','1','7aa2f7'),bytes([3,5,100,8,1,122,162,247,0,1,0,0,0,0,0,0]))
    def test_static_zones(self):
        self.assertEqual(b.zone_payloads('ff0080'),[bytes([z,255,0,128]) for z in [1,2,4,8]])
    def test_reject_unsupported_modes(self):
        for mode in ['6','7','-1','256']:
            with self.assertRaises(ValueError): b.effect_payload(mode,'5','100','1','ffffff')
    def test_reject_invalid_parameters(self):
        for params in [('1','10','100','1','ffffff'),('1','5','101','1','ffffff'),('1','5','100','3','ffffff'),('1','5','100','1','zzzzzz')]:
            with self.assertRaises(ValueError): b.effect_payload(*params)
    def test_fan_presets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); hw=root/'hwmon0'; hw.mkdir()
            (hw/'name').write_text('acer')
            for n in (1,2):
                (hw/f'pwm{n}_enable').write_text('2')
                (hw/f'pwm{n}').write_text('100')
            with patch.object(b, 'HWMON', root):
                b.set_fan('100')
                self.assertEqual([(hw/f'pwm{n}_enable').read_text() for n in (1,2)],['0','0'])
                b.set_fan('auto')
                self.assertEqual([(hw/f'pwm{n}_enable').read_text() for n in (1,2)],['2','2'])
                b.set_fan('70')
                self.assertEqual([(hw/f'pwm{n}_enable').read_text() for n in (1,2)],['1','1'])
                self.assertEqual([(hw/f'pwm{n}').read_text() for n in (1,2)],['178','178'])
                with self.assertRaises(ValueError): b.set_fan('0')
if __name__ == '__main__':
    unittest.main()
