from app.services import scale_service, compare_service
from app.audio_dsp import dtw_aligner
from tests.test_alpha2_learning import _tone_wav


def test_hue_non_tempered_tables_pinned():
    assert scale_service.SCALE_CENTS["bac"] == [0.0, 154.0, 386.0, 498.0, 702.0]
    assert scale_service.SCALE_CENTS["nam"] == [0.0, 154.0, 386.0, 631.0, 702.0]
    assert scale_service.SCALES["bac"]["note_names"][:5] == ["Cung", "Thương", "Tần", "Xứng", "Phu"]


def test_scale_reference_uses_non_tempered_frequencies():
    bac = scale_service.SCALES["bac"]["frequencies"]
    assert abs(bac[0] - 261.63) < 0.5
    assert abs(bac[1] - 261.63 * (2 ** (154 / 1200))) < 1.0
    assert abs(bac[2] - 261.63 * (2 ** (386 / 1200))) < 1.0
    assert abs(bac[4] - 261.63 * (2 ** (702 / 1200))) < 1.0
    assert len(bac) == 6


def test_tempered_re_within_tolerance_of_thuong():
    c = scale_service._cents_class(293.66)
    d = scale_service._min_cents_distance(c, scale_service.SCALE_CENTS["bac"])
    assert d <= scale_service.SCALE_MATCH_TOLERANCE_CENTS


def test_out_of_scale_note_rejected():
    c = scale_service._cents_class(466.16)
    d = scale_service._min_cents_distance(c, scale_service.SCALE_CENTS["bac"])
    assert d > scale_service.SCALE_MATCH_TOLERANCE_CENTS


def test_scale_transpose_shifts_centers():
    centers0 = scale_service._scale_centers("bac", 0)
    centers2 = scale_service._scale_centers("bac", 2)
    assert abs((centers2[0] - centers0[0]) % 1200.0 - 200.0) < 1.0


def test_dtw_band_widened_for_slow_practice():
    assert dtw_aligner.BAND_RATIO >= 0.25
    assert dtw_aligner.MIN_BAND >= 16


def test_ornament_vibrato_not_over_penalized():
    ref = _tone_wav([220.0, 330.0], tone_len=1.2)
    r = compare_service.compare(ref, _tone_wav([220.0, 330.0], tone_len=1.2, vib=60))
    m = r["metrics"]
    assert m["stability_score"] >= 70
    assert m["score"] >= 90
