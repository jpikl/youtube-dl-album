#!/bin/sh

# youtube-dl-album.sh - download an album from youtube and write a
# cuesheet file or split into track files
# uses regular expressions to extract track listings from video
# descriptions
#
# usage: youtube-dl-album.sh [options] <url|video id>
#


DEFAULT_TRACK_FORMAT="%t %o"
DEFAULT_TITLE_FORMAT="%p - %a"

TITLE_RE='.*'
OFFSET_RE='(\\d{1,2}:)?\\d{1,2}:\\d{1,2}'

ALBUM_RE='.*'
PERFORMER_RE='.*'

usage () {
	echo "usage: youtube-dl-album.sh [options] url"
	echo
	echo "youtube-dl-album.sh downloads an album from youtube and writes a cuesheet"
	echo "or split tracks based on information extracted from the video description"
	echo
	echo "options"
	echo " -s	split tracks (overrides writing of a cuesheet)"
	echo " -i	read album descrption from stdin"
	echo " -l	offsets are track lengths"
	echo " -f	track format string (default: '$DEFAULT_TRACK_FORMAT')"
	echo " -t	title format string (default: '$DEFAULT_TITLE_FORMAT')"
	echo " -h	print this help message"
	echo
	echo "format specifiers"
	echo
	echo " track"
	echo "  %t	track title ('$TITLE_RE')"
	echo "  %o	track offset ('$OFFSET_RE')"
	echo
	echo " title"
	echo "  %p	album performer/artist ('$PERFORMER_RE')"
	echo "  %a	album title ('$ALBUM_RE')"
	echo
	echo " format strings can be intermixed with regex, eg."
	echo
	echo "	youtube-dl-album.sh -f \"\d+ %t %o\" ..."
	echo
	echo " will filter track numbers out of the track title string"
}

die () {
	fmt="$1"
	shift
	printf "$fmt\n" $@ >&2
	exit 1
}

YTDL_OPT='-x --no-mtime -o %(title)s.%(ext)s'

download () {
	youtube-dl $YTDL_OPT $1 | tee /dev/tty
}

# get the "*.description" file name from youtube-dl output
get_desc_file () {
	printf "%s" "$1" | sed -n "s/\[info\] Writing video description to: //p"
}

# get the album file name from youtube-dl output
get_album_file () {
	printf "%s" "$1" | sed -n "s/\[ffmpeg] Destination: //p"
}

# transform track format argument into regex pattern
build_track_pattern () {

	printf "%s" "$1" | sed \
		-e "s/%t/(?<title>$TITLE_RE)/" \
		-e "s/%o/(?<offset>$OFFSET_RE)/"
}

scan_tracks () {
	printf "%s" "$1" | perl -lne \
		"if (/$2/) {
			print qq(\$+{offset}\t\$+{title})
		}"
}

build_title_pattern () {

	printf "%s" "$1" | sed \
		-e "s/%a/(?<album>$ALBUM_RE)/" \
		-e "s/%p/(?<performer>$PERFORMER_RE)/"
}

scan_title () {
	eval "$(printf "%s" "$1" | perl -lne \
		"if (/$2/) {
			print qq(
				$3=\"\$+{album}\"
				$4=\"\$+{performer}\"
			)
		}"
	)"
}

unpack_time () {
	eval "$2=${1%%:*} $3=${1##*:}"
}

# There is a small chance the album runs longer than one hour or is
# a multi-CD. The hour field needs to be removed and added to the
# minutes value for cuesheets
hours_to_minutes () {
	printf "%s\n" "$1" | while read offset title
	do
		printf "%s" "$offset" | (
			IFS=':' read hours minutes seconds
			if [ "$seconds" ]
			then
				minutes=$((minutes + (hours * 60)))
			else
				seconds=$minutes
				minutes=$hours
			fi
			printf "%02s:%02s\t%s\n" "$minutes" "$seconds" "$title"

		)
	done
}

# Calculate track offsets from length times - helpful for when offset
# information isn't provided but track length is, such as in a listing
# from wikipedia
calc_offsets () {
	offmin=0
	offsec=0

	while read length title
	do
		printf "%02d:%02d\t%s\n" "$offmin" "$offsec" "$title"

		unpack_time $length lenmin lensec

		offsec=$((offsec + lensec))
		offmin=$((offmin + lenmin + (offsec / 60)))
		offsec=$((offsec % 60))
	done
}

get_album_length () {
	ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$1"
}

diff_time () {
	unpack_time $1 min1 sec1
	unpack_time $2 min2 sec2

	min_diff=$((min2 - min1))
	sec_diff=$((sec2 - sec1))

	if [ $sec_diff -lt 1 ]
	then
		min_diff=$((min_diff - 1))
		sec_diff=$((sec_diff + 60))
	fi

	printf "%02d:%02d" $min_diff $sec_diff
}

# Adds a length field to the track list for use as an ffmpeg "-t duration" specifier.
calc_cut_regions () {
	printf "%s\n" "$1" | (
		read prev title

		while read offset next_title
		do
			length="$(diff_time "$prev" "$offset")"
			printf "%s\t%s\t%s\n" "$prev" "$length" "$title"

			prev="$offset"
			title="$next_title"
		done

		printf "%s\t%s\t%s\n" "$prev" "$2" "$title"
	)
}

# option -s
# split album audio file into individual tracks using ffmpeg
split_tracks () {
	ext=${1##*.}

	eval "ffmpeg -hide_banner -i \"$1\" $(
		calc_cut_regions "$2" "$(get_album_length "$1")" | (
			while read offset length title
			do
				n=$((n + 1))
				printf " -acodec copy -ss %s -t %s \"%02d %s.%s\"" $offset $length $n "$title" "$ext"
			done
		)
	)"

}

# Write a cuesheet file containing the album track information.
# This is useful for music players able to interpret cuesheet files
# or for splitting with shntool
# overriden by -s
write_cue () {
	# NOTE: filetype can be anything
	cat - <<HEADER
FILE "$1" MP3
TITLE "$2"
PERFORMER "$3"
HEADER

	printf "%s\n" "$4" | while read offset title
	do
		n=$((n + 1))
		nf=$(printf "%02d" $n)

		cat - <<TRACK
	TRACK $nf AUDIO
		INDEX 01 $offset:00
		TITLE "$title"
TRACK
	done
}

main () {
	OPTIONS="silf:t:h"

	USE_DESC="yes"
	SPLIT_TRACKS=
	CALC_OFFSETS=


	while getopts "$OPTIONS" opt
	do
		case "$opt" in
			s)
				SPLIT_TRACKS="yes"
				;;
			i)
				USE_DESC=
				;;
			l)
				CALC_OFFSETS="yes"
				;;
			f)
				track_format="$OPTARG"
				;;
			t)
				title_format="$OPTARG"
				;;
			h)
				usage
				exit
				;;
			?)
				usage
				exit 1
				;;
		esac
	done

	shift $((OPTIND - 1))

	if [ "$USE_DESC" ]
	then
		YTDL_OPT="$YTDL_OPT --write-description"
	fi

	if [ -z "$track_format" ]
	then
		track_format="$DEFAULT_TRACK_FORMAT"
	fi

	if [ -z "$title_format" ]
	then
		title_format="$DEFAULT_TITLE_FORMAT"
	fi

	output=$(download "$1")

	if [ ! $? ]
	then
		die "Failed to download album: '%s'" "$1"
	fi

	if [ "$USE_DESC" ]
	then
		desc="$(cat "$(get_desc_file "$output")")"
	else
		desc="$(cat -)"
	fi


	track_pattern="$(build_track_pattern "$track_format")"
	tracks="$(scan_tracks "$desc" "$track_pattern")"

	if [ -z "$tracks" ]
	then
		die "Didn't get any track information with format: '%s' and description:\n%s" \
			"$format" "$desc"
	fi

	tracks="$(hours_to_minutes "$tracks")"

	if [ "$CALC_OFFSETS" ]
	then
		tracks="$(calc_offsets "$tracks")"
	fi

	file="$(get_album_file "$output")"

	title_pattern="$(build_title_pattern "$title_format")"
	scan_title "${file%.*}" "$title_pattern" album performer


	if [ "$SPLIT_TRACKS" ]
	then
		split_tracks "$file" "$tracks"
	else
		cuefile="$performer - $album.cue"
		printf "Writing cuefile: '%s'...\n" "$cuefile"
		write_cue "$file" "$album" "$performer" "$tracks" > "$cuefile"
	fi
}

main "$@"

