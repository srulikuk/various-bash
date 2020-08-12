#!/bin/bash
# Source vars from lc_src.sh (create it based on src.sh example)
c_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if ! [[ -f ${c_dir}/lc_analyse.cfg ]] ; then
  printf 'lc_analyse.cfg file is required but not found in %s\nEXIT\n' "$c_dir"
  exit
fi
shopt -q extglob || shopt -s extglob # turn on extglob

source "${c_dir}/lc_analyse.cfg"

tmp=("${r_dir}"_*)
f_dir="${tmp[-1]}"

if [[ -f "${f_dir}/from" ]] ; then
  header+=("from")
fi
if [[ -f "${f_dir}/subject" ]] ; then
  header+=("subject")
fi
if [[ -z ${header[*]} ]] ; then
  printf 'The files %s/from and %s/subject do not exist\nEXIT\n' "$f_dir" "$f_dir"
  exit
fi

e_time="${f_dir##*_}"

# prepare spammassin rules
for file in "${header[@]}" ; do
  count=1
  file_p="${f_dir}/${file}"
  cp "$file_p" "${file_p}.cf"
  while read -r line ; do
    line=$(sed 's/ \+/\\s+/g' <<< "$line")
    line_a=$(printf 'header LOCAL_%s_%s_%s\t%s =~' "$e_time" "$count" "${file^^}" "${file^}")
    line_b=$(printf 'score LOCAL_%s_%s_%s\t%s\n' "$e_time" "$count" "${file^^}" "$score")
    sed -i "s;$line;$line_a $line\n$line_b\n;" "${file_p}.cf"
    count=$((count + 1))
  done < "$file_p"
  printf '%s.cf has been updated, place the rules in /etc/spamassassin/custom_%s.cf\n' "$file_p" "$file"
done

printf 'Test the SA files by running "spamassassin --lint"\n'
printf 'For the changes to take a effect restart the following services\n systemctl restart spamassassin\n systemctl restart amavisd-new\n'
