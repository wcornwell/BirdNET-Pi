import logging

# Simplified filter_humans logic for verification
def filter_humans_logic(predictions, priv_thresh, human_names=None):
    if priv_thresh == 0.0:
        return predictions

    human_cutoff = max(1, int(priv_thresh))
    # print(f"DEBUG: HUMAN-CUTOFF AT RANK: {human_cutoff}")

    if human_names is None:
        human_names = set()

    human_mask = [False] * len(predictions)
    human_labels = [None] * len(predictions)
    
    for i, prediction in enumerate(predictions):
        for rank, p in enumerate(prediction[:human_cutoff], 1):
            # NEW: Case-insensitive check for broad keywords
            label_name = p[0].lower()
            privacy_keywords = ['human', 'homo sapiens', 'engine', 'siren', 'noise', 'screech', 'whistle']
            if any(key in label_name for key in privacy_keywords) or p[0] in human_names:
                # print(f"INFO: Privacy filter ACTIVE: Sensitive sound detected at rank {rank} (conf: {p[1]}, label: {p[0]})")
                human_mask[i] = True
                human_labels[i] = p
                break

    # Neighbor filtering disabled
    human_neighbour_mask = [False] * len(predictions)

    clean_detections = []
    for prediction, human, has_human_neighbour, h_label in zip(predictions, human_mask, human_neighbour_mask, human_labels):
        if human or has_human_neighbour:
            # NEW: FORCE confidence to 0.0 and label to 'Human'
            prediction = [('Human', 0.0)]
        else:
            prediction = prediction[:10]
        clean_detections.append(prediction)

    return clean_detections

def run_tests():
    print("--- Running Privacy Filter Verification ---")
    
    # Test 1: 1% threshold (Rank 1)
    print("\nTest 1: 1% threshold, Human at rank 2")
    preds = [[('Bird', 0.9), ('Human', 0.8)]]
    result = filter_humans_logic(preds, 1.0)
    assert result == [[('Bird', 0.9), ('Human', 0.8)]], f"Expected no mask, got {result}"
    print("SUCCESS: 1% didn't block Rank 2")

    # Test 2: 2% threshold (Rank 2)
    print("\nTest 2: 2% threshold, Human at rank 2")
    result = filter_humans_logic(preds, 2.0)
    assert result == [[('Human', 0.0)]], f"Expected mask [('Human', 0.0)], got {result}"
    print("SUCCESS: 2% blocked Rank 2 with 0.0 confidence")

    # Test 3: Neighbor filtering check
    print("\nTest 3: Neighbor filtering check")
    preds = [[('Bird', 0.9)], [('Human', 0.9)], [('Bird', 0.8)]]
    result = filter_humans_logic(preds, 1.0)
    assert result[0] == [('Bird', 0.9)], "Neighbor 0 should NOT be masked"
    assert result[1] == [('Human', 0.0)], "Center should be masked with 0.0 confidence"
    assert result[2] == [('Bird', 0.8)], "Neighbor 2 should NOT be masked"
    print("SUCCESS: Neighbor filtering is OFF and confidence is 0.0")

    # Test 4: Engine keyword check at 1%
    print("\nTest 4: Engine keyword check at 1%")
    preds = [[('Homo sapiens_Engines', 0.8), ('Bird', 0.1)]]
    result = filter_humans_logic(preds, 1.0)
    assert result == [[('Human', 0.0)]], f"Expected mask [('Human', 0.0)], got {result}"
    print("SUCCESS: 'Engines' was blocked and confidence set to 0.0")

    # Test 5: Homo sapiens keyword check at 1%
    print("\nTest 5: Homo sapiens keyword check at 1%")
    preds = [[('Homo sapiens_Human Voice', 0.9), ('Bird', 0.1)]]
    result = filter_humans_logic(preds, 1.0)
    assert result == [[('Human', 0.0)]], f"Expected mask [('Human', 0.0)], got {result}"
    print("SUCCESS: 'Homo sapiens' was blocked and confidence set to 0.0")

    print("\n--- All Smart Tests Passed! ---")

if __name__ == "__main__":
    run_tests()
