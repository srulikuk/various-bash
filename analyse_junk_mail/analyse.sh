#!/bin/bash

# Source all vars from lc_src.sh (create it based on src.sh example)
c_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if ! [[ -f ${c_dir}/lc_analyse.cfg ]] ; then
  printf 'lc_analyse.cfg file is required but not found in %s\nEXIT\n' "$c_dir"
  exit
fi
shopt -q extglob || shopt -s extglob # turn on extglob

source "${c_dir}/lc_analyse.cfg"

f_date=$(date +%s) # date for dir names
w_dir="${w_dir}_$f_date"
r_dir="${r_dir}_$f_date"

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
if [[ -f ${c_dir}/lc_last.run ]] ; then
  last_date[0]="-newermt"
  last_date[1]="$(date '+%Y-%m-%d %H:%M:%S' -d @"$(<"${c_dir}/lc_last.run")")"
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
    grep '^From: ' "$file" | sed 's/^From: //; s/<.*//; s/"/./g; s/\\/./g; s/\//./g; s/[[:blank:]]*$//; s/  //g' >> "${w_dir}/from_line.tmp" # using sed as <email> might be on next line
    mapfile -t tmp < <(grep -A1 '^Subject: ' "$file" | sed 's/^Subject: //; s/"/./g; s/\\//g; s/\//./g; s/  //g') # subject line can sometimes be split over 2 lines
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
    if [[ -f "/etc/spamassassin/custom_${name}.cf" ]] ; then
      if grep -iq " ${name} =~ .*${line}" "/etc/spamassassin/custom_${name}.cf"; then
        # if there is check if its exact match
        if grep -iq "[(|]${line}[|)]" "/etc/spamassassin/custom_${name}.cf"; then
          # If its an exact match consider changing the score
          if ! [[ -f ${w_dir}/info_same ]] ; then
            printf '\n\n# NOTE: Still getting spam with following in %s header. Consider
  # changing the score for following in /etc/spamassassin/custom_%s.cf;\n' "$name" "$name" > "${w_dir}/info_same"
            same_e=1
          fi
          printf '# Line #%s - "%s"\n' "$(grep -in "[(|]${line}[|)]" "/etc/spamassassin/custom_${name}.cf" | awk -F":" '{print $1}')" "$line" >> "${w_dir}/info_same"
          continue
        else
          # if its a shorter match consider replacing the match
          if ! [[ -f ${w_dir}/info_short ]] ; then
            printf '\n\n# NOTE: Consider changing the following %s header
  # match to the shorter ones /etc/spamassassin/custom_%s.cf;\n' "$name" "$name" > "${w_dir}/info_short"
            short_e=1
          fi
          printf '# Line #%s: shorter match: "%s"\n' "$(grep -in " ${name} =~ .*${line}" "/etc/spamassassin/custom_${name}.cf" | awk -F":" '{print $1}')" "$line" >> "${w_dir}/info_short"
        fi
        continue
      fi
    fi

    # Continue with unmatched lines
    count=$(grep -c "^${line}$" "${w_dir}/${file}.tmp")
    if ((count > 3)) ; then # dont bother with anything that does not have at least x matches
      printf '%s, %s\n' "$count" "$line" >> "${r_dir}/${file}"
    fi
  done < "${w_dir}/$file"
  sort -n "${r_dir}/${file}" > "${r_dir}/${file}.tmp"
  mv "${r_dir}/${file}.tmp" "${r_dir}/${file}"
#  out_msg+=("Result for $file is at ${r_dir}/${file}")

done

if ((same_e == 1)) ; then
  cat "${w_dir}/info_same" > "${r_dir}/notes"
  notes_e=1
fi
if ((short_e == 1)) ; then
  cat "${w_dir}/info_short" >> "${r_dir}/notes"
  notes_e=1
fi

for file in subject_line from_line ; do
  if [[ -f ${r_dir}/${file} ]] ; then
    out_msg+=("Result for $file is at ${r_dir}/${file}")
    result_e=1
  fi
done
if ((result_e != 1)) ; then
  out_msg+=("No new spam phrases have been found")
else
  sa_msg="\nTo create spamassassin rules ready  to place in the SA config files
amend put the phrases for each properly formatted in its respective
file $r_dir/from & $r_dir/subject
 -i.e /(phrase 1|phrase 2|.phrase 3.|phrase 4|etc...)/i
and run \"${c_dir}/sa_rules.sh\"\n"
fi
((notes_e == 1)) && out_msg+=("Some NOTES about existing matches in ${r_dir}/_notes")
out_msg+=("To delete the tmp files run rm -r $w_dir")

if [ -t 1 ] ; then
  printf '\nUpdate last run time? [y/n] > '
  read -r
  [[ $REPLY =~ ^(y|yes)$ ]] && run_date=1
else
  run_date=1
fi
((run_date == 1)) && printf '%s' > "${c_dir}/lc_last.run" "$current_date"

printf '%b\n' "${out_msg[@]}"
printf '%b\n' "$sa_msg"

"$@"
