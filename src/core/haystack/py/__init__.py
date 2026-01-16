# Hand-written haystack module for Python
# Contains native implementations that mirror the ES/JavaScript versions

# Patch Number._make_duration_body to fix negative duration unit selection
def _patch_number():
    from fan.haystack.Number import Number
    from fan.sys.ObjUtil import ObjUtil
    from fan.sys.Duration import Duration

    def _make_duration_body_fixed(self, dur, unit=None):
        """Fixed version that uses absolute value for magnitude comparison."""
        if unit is None:
            # Use absolute value for magnitude comparison (fixes negative duration unit selection)
            abs_dur = dur.abs_()
            if ObjUtil.compare_lt(abs_dur, Duration.make(1000000000)):
                unit = Number.ms()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(60000000000)):
                unit = Number.sec()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(3600000000000)):
                unit = Number.mins()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(86400000000000)):
                unit = Number.hr()
            else:
                unit = Number.day()

        self._float_ = ((ObjUtil.to_float(ObjUtil.coerce(dur.ticks(), "sys::Num")) / 1.0E9) / unit.scale())
        self._unit_ref = unit

    Number._make_duration_body = _make_duration_body_fixed

try:
    _patch_number()
except ImportError:
    pass  # Number not yet loaded
