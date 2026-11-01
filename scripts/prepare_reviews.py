"""
prepare_reviews.py
------------------
WHY THIS SCRIPT EXISTS
  The raw reviews CSV has 104,720 physical lines but only 99,224 data rows.
  The extra ~5,500 lines are literal newline characters that sit inside
  quoted comment fields (review_comment_title, review_comment_message).
  SQL*Loader uses the row terminator to find where one record ends and the
  next begins, so those embedded newlines confuse it and cause wrong splits.

WHAT IT DOES
  - Reads the raw file using Python's csv module, which understands RFC-4180
    quoting and handles embedded newlines correctly.
  - Replaces every embedded newline variant (\r\n, \n, \r) inside a field
    value with a single space, so the text stays readable.
  - Writes a "flat" output file where every record is exactly one line,
    terminated by bare \n (LF only).
  - Quotes ALL fields (csv.QUOTE_ALL) so SQL*Loader can safely parse commas
    inside text.

EXPECTED OUTPUT
  Rows written including header: 99225
  (1 header + 99224 data rows = 99225 total lines in the output file)

RUN FROM THE PROJECT ROOT:
  python scripts\prepare_reviews.py
"""

import csv

# Source: original raw file (never modify this file)
src = r'data\raw\olist_order_reviews_dataset.csv'

# Destination: prepared file that SQL*Loader will read
dst = r'data\prepared\olist_order_reviews_prepared.csv'

n = 0
with open(src, newline='', encoding='utf-8') as fin, \
     open(dst, 'w', newline='', encoding='utf-8') as fout:

    reader = csv.reader(fin)
    # lineterminator='\n' means the output uses bare LF — no embedded CRLF
    writer = csv.writer(fout, quoting=csv.QUOTE_ALL, lineterminator='\n')

    for row in reader:
        # Replace all three newline styles with a single space inside each field
        cleaned = [
            f.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ')
            for f in row
        ]
        writer.writerow(cleaned)
        n += 1

print('Rows written including header:', n)
# If this prints 99225, the file is correct and SQL*Loader will load it cleanly.
# If you see a different number, stop and paste the output here before proceeding.
