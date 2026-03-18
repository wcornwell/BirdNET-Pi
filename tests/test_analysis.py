import os
import unittest
from unittest.mock import patch

from scripts.utils.analysis import run_analysis
from scripts.utils.classes import ParseFileName
from tests.helpers import TESTDATA, Settings
from scripts.utils.analysis import filter_humans


class TestRunAnalysis(unittest.TestCase):

    def setUp(self):
        source = os.path.join(TESTDATA, 'Pica pica_30s.wav')
        self.test_file = os.path.join(TESTDATA, '2024-02-24-birdnet-16:19:37.wav')
        if os.path.exists(self.test_file):
            os.unlink(self.test_file)
        os.symlink(source, self.test_file)

    def tearDown(self):
        if os.path.exists(self.test_file):
            os.unlink(self.test_file)

    @patch('scripts.utils.helpers._load_settings')
    @patch('scripts.utils.analysis.loadCustomSpeciesList')
    def test_run_analysis(self, mock_loadCustomSpeciesList, mock_load_settings):
        # Mock the settings and species list
        mock_load_settings.return_value = Settings.with_defaults()
        mock_loadCustomSpeciesList.return_value = []

        # Test file
        test_file = ParseFileName(self.test_file)

        # Expected results
        expected_results = [
            {"confidence": 0.912, 'sci_name': 'Pica pica'},
            {"confidence": 0.9316, 'sci_name': 'Pica pica'},
            {"confidence": 0.8857, 'sci_name': 'Pica pica'}
        ]

        # Run the analysis
        detections = run_analysis(test_file)

        # Assertions
        self.assertEqual(len(detections), len(expected_results))
        for det, expected in zip(detections, expected_results):
            self.assertAlmostEqual(det.confidence, expected['confidence'], delta=1e-4)
            self.assertEqual(det.scientific_name, expected['sci_name'])


class TestFilterHumans(unittest.TestCase):

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_no_human(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections without humans
        detections = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_C', 0.7), ('Bird_D', 0.6)]
        ]

        # Expected output
        expected = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_C', 0.7), ('Bird_D', 0.6)]
        ]

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_empty(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections without humans
        detections = []

        # Expected output
        expected = []

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_with_human(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections with humans
        detections = [
            [('Human', 0.95), ('Bird_A', 0.8)],
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_C', 0.9), ('Bird_D', 0.8)],
            [('Bird_B', 0.7), ('Human vocal_Human vocal', 0.9)]
        ]

        # Expected output (since neighbor filtering is off, only index 0 and 3 are masked if detected)
        # However, settings default PRIVACY_THRESHOLD is 0 in with_defaults(), 
        # but filter_humans might be called with implicit defaults. 
        # In TestFilterHumans, we need to set a threshold to trigger it.
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 1
        mock_load_settings.return_value = settings

        expected = [
            [('Human', 0.0)],
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_C', 0.9), ('Bird_D', 0.8)],
            [('Human', 0.0)]
        ]

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_with_human_neighbour(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections with human neighbours
        detections = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Human_Human', 0.95), ('Bird_C', 0.7)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Expected output (Neighbor filtering OFF)
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 1
        mock_load_settings.return_value = settings

        expected = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Human', 0.0)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_with_deep_human(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections with human neighbours
        detections = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Bird_C', 0.7)] * 10 + [('Human_Human', 0.95)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Expected output (Neighbor filtering OFF, human at rank 11, threshold 1% => rank 1)
        # result: NO MASKING because human is at rank 11
        expected = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Bird_C', 0.7)] * 10 + [('Human', 0.95)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_with_human_deep(self, mock_load_settings):
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 1
        mock_load_settings.return_value = settings

        # Input detections with human neighbours
        detections = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Bird_C', 0.7)] * 10 + [('Human_Human', 0.95)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Expected output (Threshold 1% => rank 1 checks)
        # Human at rank 11, so NO masking
        expected = [
            [('Bird_A', 0.9), ('Bird_B', 0.8)],
            [('Bird_D', 0.9), ('Bird_E', 0.8)],
            [('Bird_C', 0.7)] * 10 + [('Human', 0.95)],
            [('Bird_F', 0.6), ('Bird_G', 0.5)]
        ]

        # Run filter_humans
        result = filter_humans(detections)

        # Assertions
        self.assertEqual(result, expected)

    @patch('scripts.utils.helpers._load_settings')
    def test_filter_humans_with_custom_name(self, mock_load_settings):
        mock_load_settings.return_value = Settings.with_defaults()

        # Input detections with a name that is in the human_names set
        # This simulates a custom classifier where the label was stripped to "Homo sapiens"
        detections = [
            [('Bird_A', 0.9)],
            [('Homo sapiens', 0.95), ('Bird_B', 0.8)],
            [('Bird_C', 0.7)]
        ]

        human_names = {'Homo sapiens'}

        # Expected output: Only the second one masked as human, neighbor filtering is OFF
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 1
        mock_load_settings.return_value = settings

        expected = [
            [('Bird_A', 0.9)],
            [('Human', 0.0)],
            [('Bird_C', 0.7)]
        ]

        # Run filter_humans with the custom name set
        result = filter_humans(detections, human_names)

        # Assertions
        self.assertEqual(result, expected)


class TestPrivacyThresholdScaling(unittest.TestCase):

    @patch('scripts.utils.helpers._load_settings')
    def test_threshold_scaling(self, mock_load_settings):
        # 5 => check top 5 predictions (absolute rank)
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 5
        mock_load_settings.return_value = settings

        # Build a 10-label prediction list (descending confidence)
        base = [(f'Bird_{i}', 1.0 - i * 0.01) for i in range(10)]

        # Human at rank 5 (index 4) should be masked.
        chunk_with_human_rank_5 = base.copy()
        chunk_with_human_rank_5[4] = ('Human', 0.5)

        # Human at rank 6 (index 5) should NOT be masked (outside top 5)
        chunk_with_human_rank_6 = base.copy()
        chunk_with_human_rank_6[5] = ('Human', 0.4)

        detections = [chunk_with_human_rank_5, chunk_with_human_rank_6]

        result = filter_humans(detections)

        self.assertEqual(result[0], [('Human', 0.0)])
        self.assertEqual(result[1][5], ('Human', 0.4))

    @patch('scripts.utils.helpers._load_settings')
    def test_threshold_scaling_small_label_set(self, mock_load_settings):
        # Threshold=1 should always check just the top label (even on huge models)
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 1
        mock_load_settings.return_value = settings

        # 14k labels - human is in position 2 (should still be masked, only top 1 checked)
        detections = [[('Bird_0', 0.9), ('Human', 0.8)] + [(f'Bird_{i}', 0.1) for i in range(2, 14000)]]

        result = filter_humans(detections)
        self.assertEqual(result, [[('Bird_0', 0.9), ('Human', 0.8)]])

    @patch('scripts.utils.helpers._load_settings')
    def test_threshold_scaling_top_n_clamp(self, mock_load_settings):
        # Threshold should clamp at the model's label count (not exceed it).
        settings = Settings.with_defaults()
        settings['PRIVACY_THRESHOLD'] = 500
        mock_load_settings.return_value = settings

        # Only 100 labels exist; human at rank 50 should be masked when threshold=500
        base = [(f'Bird_{i}', 1.0 - i * 0.01) for i in range(100)]
        base[49] = ('Human', 0.5)
        detections = [base]

        result = filter_humans(detections)
        self.assertEqual(result, [[('Human', 0.0)]])


if __name__ == '__main__':
    unittest.main()
