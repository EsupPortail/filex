#!/bin/sh
grep -r -h -P '^\s*(use|require)\s+(?!(constant|FILEX|vars|strict|POSIX|Exporter|lib|CAS)).+\;$' --include=*.pl --include=*.pm ../* | sort -u
