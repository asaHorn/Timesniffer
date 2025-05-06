This powershell script will scan a subdirectory for irregularies which are indicative of timestomping. 

USAGE:
.\timesniffer.ps1 -TargetDir [DirectoryToScan]

RULES:
RULE 1 - A files $FileName modification time is after it's $StandardInformation modification time. This is indicative of lazy or unprivilated timestomping.
RULE 2 - A files $FileName accessed time is after it's $StandardInformation accessed time. This is indicative of lazy or unprivilated timestomping.
RULE 3 - A files $FileName creation time is after it's $StandardInformation creation time. This is indicative of lazy or unprivilated timestomping.
RULE 4 - A files $FileName MFT update time is after it's $StandardInformation MFT update time. This is indicative of lazy or unprivilated timestomping.
RULE 5 - A files $StandardInformation modification time is an exact duplicate of another file in the directory. It is likely the timestamp was copied over.
RULE 6 - A files $StandardInformation accessed time is an exact duplicate of another file in the directory. It is likely the timestamp was copied over.
RULE 7 - A files $StandardInformation created time is an exact duplicate of another file in the directory. It is likely the timestamp was copied over.
RULE 8 - A files $StandardInformation MFT update time is an exact duplicate of another file in the directory. It is likely the timestamp was copied over.\

Credits
This project uses Mft2Csv by Joakim Schicht
https://github.com/jschicht/Mft2Csv
