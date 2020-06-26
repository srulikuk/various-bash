#!/bin/bash

# Source all vars from lc_src.sh (create it based on src.sh example)
c_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if ! [[ -f ${c_dir}/lc_analyse.cfg ]] ; then
  printf 'lc_analyse.cfg file is required but not found in %s\nEXIT\n' "$c_dir"
  exit
fi
shopt -q extglob || shopt -s extglob # turn on extglob

source "${c_dir}/lc_analyse.cfg"

mkdir -p "$w_dir"
mkdir -p "$r_dir"

userDetails()
{
  [[ $1 =~ ((.).*)"|"((.).*)"|"(.*) ]]
  user="${BASH_REMATCH[1]}"
  u="${BASH_REMATCH[2]}"
  domain="${BASH_REMATCH[3]}"
  d="${BASH_REMATCH[4]}"
  dir="${BASH_REMATCH[5]}"
}

# Last run time is written to lc_last.run file (in $c_dir) on
# each run, so on the  next run  it will only  analyse emails
# emails since last run date. (file is overwritten each time)
# analyse.sh will prompt if to update the lc_last.run file if
# running in test mode select 'no' to the update prompt.
last_date=()
if [[ -f ${c_dir}lc_last.run ]] ; then
  last_date[0]="-newermt"
  last_date[1]="$(date '+%Y-%m-%d %H:%M:%S' -d @"$(<"${c_dir}lc_last.run")")"
  printf 'Last run time was at %s\n' "${last_date[1]}"
fi
current_date=$(date +%s) # date for last.run file

# first lets check for each user seperatly
for i in "${email[@]}" ; do
  userDetails "$i"
  user_path="/var/spool/imap/domain/$d/$domain/$u/user/$user/$dir/"
  mapfile -t user_files < <(find "$user_path" -maxdepth 1 -type f  "${last_date[@]}" -name '*[0-9].' ! -name '*[!0-9]*.')
  for file in "${user_files[@]}" ; do
    # Get the FROM text
    grep '^From: ' "$file" | sed 's/^From: //; s/<.*//; s/"//g; s/\\//g; s/[[:blank:]]*$//' >> "${w_dir}/from_line.tmp" # using sed as <email> might be on next line
    mapfile -t tmp < <(grep -A1 '^Subject: ' "$file" | sed 's/^Subject: //') # subject line can sometimes be split over 2 lines
    if grep -q "^ " <<< "${tmp[1]}" ; then # if subject is split over 2 lines second line starts with a space
      subject=$(printf '%s\n' "${tmp[*]}" | tr -d \\r) # merge the 2 lines
    fi

    printf '%s\n' "${subject##*SPAM\*\*\* }" >> "${w_dir}/subject_line.tmp"
  done
done

sort -u "${w_dir}/from_line.tmp" > "${w_dir}/from_line"
sort -u "${w_dir}/subject_line.tmp" > "${w_dir}/subject_line"

for file in from_line subject_line ; do
  name="${file%%_*}"
  while read -r line ; do
    [[ -z $line ]] && continue
    # check if there is already a rule for this match
    if grep -iq " ${name} =~ .*\\\b${line}\\\b" /etc/spamassassin/custom.cf; then
      continue
    fi
    count=$(grep -c "^${line}$" "${w_dir}/${file}.tmp")
    if ((count > 5)) ; then # dont bother with anything that does not have at least x matches
      printf '%s, %s\n' "$count" "$line" >> "${r_dir}/${file}"
    fi
  done < "${w_dir}/$file"
  sort -n "${r_dir}/${file}" > "${r_dir}/${file}.tmp"
  mv "${r_dir}/${file}.tmp" "${r_dir}/${file}"
  out_msg+=("Result for $file is at ${r_dir}/${file}")

done

# prepare spammassin rules
for file in from_line subject_line ; do
  name="${file%%_*}"
  while read -r line ; do
    line="${line##+([0-9]), }"
    printf 'header LOCAL_%s_%s\t%s =~ /\\b%s\\b/i\n' "$current_date" "${name^^}" "${name^}" "$line" >> "${r_dir}/${name}.cf"
    printf 'score LOCAL_%s_%s\t2.6\n\n' "$current_date" "${name^^}" >> "${r_dir}/${name}.cf"
  done < "${r_dir}/$file"
done

cat "${r_dir}/from.cf" > "${r_dir}/u_custom.cf"
cat "${r_dir}/subject.cf" >> "${r_dir}/u_custom.cf"

# update date.run
out_msg+=("To delete the tmp files run rm -r $w_dir")
printf '%s\n' "${out_msg[@]}"
