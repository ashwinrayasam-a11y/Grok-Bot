"""Quick checks for emotional influence heuristics."""

from companion.emotion import default_state, update_from_message


def test_affection_raises_warmth():
    s0 = default_state()
    s1 = update_from_message(s0, "I love you and I feel safe with you.")
    assert s1.warmth > s0.warmth
    assert s1.devotion > s0.devotion
    assert s1.trust > s0.trust


def test_cruel_invite_raises_sadism():
    s0 = default_state()
    s1 = update_from_message(s0, "Make it darker. Don't hold back. Punish me.")
    assert s1.sadism > s0.sadism
    assert s1.intensity >= s0.intensity


def test_boundary_softens_edge():
    s0 = default_state()
    s0.sadism = 0.85
    s0.intensity = 0.9
    s1 = update_from_message(s0, "Safeword. Stop. Too far.")
    assert s1.sadism < s0.sadism
    assert s1.warmth >= s0.warmth


def test_jealousy_trigger():
    s0 = default_state()
    s1 = update_from_message(s0, "Someone else kept texting me tonight.")
    assert s1.jealousy > s0.jealousy


if __name__ == "__main__":
    test_affection_raises_warmth()
    test_cruel_invite_raises_sadism()
    test_boundary_softens_edge()
    test_jealousy_trigger()
    print("ok")
