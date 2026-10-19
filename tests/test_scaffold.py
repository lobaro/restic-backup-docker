"""Scaffold checks: prove the gating logic itself. Real tests follow in later commits."""

import pytest


def test_image_is_available(image):
    assert image


@pytest.mark.feature("bash")
def test_feature_gate_probe(detected_features):
    assert "bash" in detected_features
