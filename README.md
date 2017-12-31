# youtube-dl-album.sh

## usage

	youtube-dl-album.sh [options] url

 youtube-dl-album.sh downloads an album from youtube and writes a cuesheet
or split tracks based on information extracted from the video description

## options

	-s	split tracks (overrides writing of a cuesheet)
	-i	read album descrption from stdin
	-l	offsets are track lengths
	-f	track format string (default: '%t %o')
	-t	title format string (default: '%p - %a')
	-h	print this help message

## format specifiers

### track

	%t	track title ('.*')
	%o	track offset ('(\d{1,2}:)?\d{1,2}:\d{1,2}')

### title

	%p	album performer/artist ('.*')
	%a	album title ('.*')

 format strings can be intermixed with regex, eg.

	youtube-dl-album.sh -f "\d+ %t %o" ...

 will filter track numbers out of the track title string
