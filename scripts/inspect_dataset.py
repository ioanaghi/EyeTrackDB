import csv
from pathlib import Path

data_folder = Path(__file__).resolve().parent.parent / "data"

for file in data_folder.glob("*.csv"):
    print(f"\nFile: {file.name}")

    with open(file, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)

        print("Columns:", reader.fieldnames)

        count = 0
        for row in reader:
            if count == 0:
                print("First row:", row)
            count += 1

        print("Total rows:", count)