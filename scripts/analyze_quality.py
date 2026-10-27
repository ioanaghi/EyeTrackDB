import csv
import math
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

for file in sorted(DATA_DIR.glob("*.csv")):
    total = 0
    valid_left = 0
    valid_right = 0
    valid_both = 0
    valid_either = 0
    missing_both = 0

    first_timestamp = None
    last_timestamp = None

    with file.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            total += 1

            timestamp = float(row["timestamp_utc"])
            if first_timestamp is None:
                first_timestamp = timestamp
            last_timestamp = timestamp

            def is_valid(eye):
                try:
                    x = float(row[f"{eye}_gaze_x"])
                    y = float(row[f"{eye}_gaze_y"])
                    validity = int(row[f"{eye}_gaze_validity"])

                    return (
                        validity == 1
                        and math.isfinite(x)
                        and math.isfinite(y)
                    )
                except (ValueError, TypeError):
                    return False

            left = is_valid("left")
            right = is_valid("right")

            valid_left += left
            valid_right += right
            valid_both += left and right
            valid_either += left or right
            missing_both += not (left or right)

    duration = (
        last_timestamp - first_timestamp
        if first_timestamp is not None else 0
    )

    print(f"\nFILE: {file.name}")
    print(f"Total samples: {total}")
    print(f"Duration: {duration:.2f} seconds")

    if total:
        print(f"Valid left: {valid_left / total * 100:.2f}%")
        print(f"Valid right: {valid_right / total * 100:.2f}%")
        print(f"Valid both: {valid_both / total * 100:.2f}%")
        print(f"Valid either: {valid_either / total * 100:.2f}%")
        print(f"No valid gaze: {missing_both / total * 100:.2f}%")