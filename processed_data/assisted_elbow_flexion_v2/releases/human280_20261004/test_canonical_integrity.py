"""Release membership/authority/leakage tests, with no model imports."""
import copy,json,unittest
from load_canonical import RELEASE,load_canonical,validate_rows,assert_source_grouping

class CanonicalIntegrity(unittest.TestCase):
    def setUp(self):
        self.rows=load_canonical();self.contract=json.loads((RELEASE/'CANONICAL_CONTRACT.json').read_text())
        self.review=json.loads((RELEASE/self.contract['authoritative_review_file']).read_text())
    def check_rows(self):return validate_rows(self.rows,self.contract,self.review)
    def test_exact_review_membership(self):self.assertEqual(len(self.check_rows()),280)
    def test_administrative_defaults_do_not_exclude(self):
        self.assertTrue(any(r['reviewer']=='' and r['review_boundaries_verified_checkbox']=='False' and r['review_subject_verified_checkbox']=='False' for r in self.rows))
        for r in self.rows:
            r['reviewer']='';r['review_boundaries_verified_checkbox']='False';r['review_subject_verified_checkbox']='False'
        self.assertEqual(len(self.check_rows()),280)
    def test_unreviewed_id_rejected(self):
        self.rows[0]['repetition_id']=self.contract['excluded_repetition_ids'][0]
        with self.assertRaises(ValueError):self.check_rows()
    def test_legacy_extra_sample_rejected(self):
        self.rows.append(copy.deepcopy(self.rows[0]))
        with self.assertRaises(ValueError):self.check_rows()
    def test_four_class_label_rejected(self):
        self.rows[0]['label']='LeftCorrect'
        with self.assertRaises(ValueError):self.check_rows()
    def test_changed_human_label_rejected(self):
        self.rows[0]['label']='Incorrect' if self.rows[0]['label']=='Correct' else 'Correct'
        with self.assertRaises(ValueError):self.check_rows()
    def test_changed_human_hand_rejected(self):
        self.rows[0]['hand']='Left' if self.rows[0]['hand']=='Right' else 'Right'
        with self.assertRaises(ValueError):self.check_rows()
    def test_silent_trimming_rejected(self):
        self.rows[0]['end_frame']=str(int(self.rows[0]['end_frame'])-1)
        with self.assertRaises(ValueError):self.check_rows()
    def test_source_mismatch_rejected(self):
        self.rows[0]['source_sha256']='wrong'
        with self.assertRaises(ValueError):self.check_rows()
    def test_source_leakage_rejected(self):
        split={r['repetition_id']:'fold_a' for r in self.rows};split[self.rows[0]['repetition_id']]='fold_b'
        with self.assertRaises(ValueError):assert_source_grouping(self.rows,split)
    def test_source_grouped_partition_allowed(self):
        sources=sorted({r['source_sha256'] for r in self.rows})
        assignment={r['repetition_id']:f'fold_{sources.index(r["source_sha256"])%3}' for r in self.rows}
        self.assertTrue(assert_source_grouping(self.rows,assignment))

if __name__=='__main__':unittest.main(verbosity=2)
