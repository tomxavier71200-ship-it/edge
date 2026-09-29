// What each main screen shows, for its ⓘ (see InfoButton).
//
// Each entry says what the numbers are, what they are compared against, and
// where the line is between a wellness reading and a medical one. They name
// the method the code actually uses; change them together with it.

const kInfoHome =
    'Your three scores for the day. Recovery is read from last night: your '
    'heart-rate variability, resting heart rate and sleep, each compared with '
    'your own recent nights, not with other people. Strain is how hard the day '
    'has been, from 0 to 21. Sleep is how much of the sleep you needed you got.';

const kInfoHealth =
    'Overview puts last night\'s vitals against your own usual range, the '
    'shaded part of each bar, drawn from up to 30 earlier nights once there are '
    'at least 7. Live HR is your heart rate as the band sends it, and is not '
    'saved. Stress is read from heart-rate variability in 15-minute windows '
    'while you are awake. None of this is a medical test.';

const kInfoRecovery =
    'How ready your body is today, from 0 to 100%. It weighs last night\'s '
    'heart-rate variability and resting heart rate against your own 28-day '
    'baseline, together with how much of your sleep need you met. It needs a '
    'scored night; without one it shows nothing rather than a guess.';

const kInfoStrain =
    'How much load the day has put on your heart, from 0 to 21. It builds from '
    'the time you spend with a raised heart rate. The shaded band is today\'s '
    'target, set '
    'from this morning\'s recovery.';

const kInfoSleep =
    'How long you slept, when, and how the night was split into stages. Sleep '
    'performance is the time you slept against the sleep you needed, which '
    'grows with the day\'s strain and any sleep you owe from earlier nights. '
    'Stages are estimated from heart rate and movement, not measured.';

const kInfoWorkout =
    'Start a workout to record it with heart rate, zones and strain. Zones use '
    'your age and, once the band has seen them, your real maximum and resting '
    'heart rate. After a workout you can rate how hard it felt.';

const kInfoTrends =
    'Each metric over time, one value per day. Missing days stay as gaps in '
    'the line rather than being filled in. The shaded band is your usual range.';
