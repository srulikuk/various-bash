#!/bin/bash

# Source all vars from lc_src.sh (create it based on src.sh example)
c_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "${c_dir}/lc_src.sh"

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

# first lets check for each user seperatly
for i in "${email[@]}" ; do
  userDetails "$i"
  user_path="/var/spool/imap/domain/$d/$domain/$u/user/$user/$dir/"
  mapfile -t user_files < <(find "$user_path" -maxdepth 1 -type f -name '*[0-9].' ! -name '*[!0-9]*.')
  for file in "${user_files[@]}" ; do
    # Get the FROM text
    grep '^From: ' "$file" | sed 's/<.*//; s/"//g; s/\\//g' >> "${w_dir}/from_line" # using sed as <email> might be on next line
    mapfile -t tmp < <(grep -A1 '^Subject: ' "$file") # subject line can sometimes be split over 2 lines
    if grep -q "^ " <<< "${tmp[1]}" ; then # if subject is split over 2 lines second line starts with a space
      subject=$(printf '%s\n' "${tmp[*]}" | tr -d \\r) # merge the 2 lines
    fi
    printf '%s\n' "${subject##*SPAM\*\*\* }" >> "${w_dir}/subject_line"
  done
done

for file in from_line subject_line ; do
  while read -r line ; do
    count=$(grep -c "$line" "${w_dir}/$file")
    if ((count > 1)) ; then
      printf '%s, %s\n' "$count" "$line" >> "${r_dir}/${file}"
    fi
  done < "${w_dir}/$file"
  sort -n "${r_dir}/${file}" > "${r_dir}/${file}.tmp"
  mv "${r_dir}/${file}.tmp" "${r_dir}/${file}"
  out_msg+=("Result for $file is at ${r_dir}/${file}")
done

printf '%s\n' "${out_msg[@]}"
