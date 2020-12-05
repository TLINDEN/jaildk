#!/bin/sh

# parse /etc/jail.conf, better version

parse() {
    file=$1

    egrep -v '^ *#|^$' $file \
    | awk '/^[a-zA-Z0-9\*]/ {
              # extract the jail name
              gsub(/\s*\{/, "");     # remove trailing parenthesis
              gsub(/\*/, "any");     # rename *
              jail = $0;
          }
          /=/ {
              # key value pair
              gsub(/^\s*/, "");      # remove leading spaces
              gsub(/;.*/, "");       # remove trailing semicolong
              gsub(/\s*=\s*/, "=");  # remove spaces around =
              if(/\.[a-zA-Z0-9_]*=/) {
                # replace dot in variable name with underscore
                sub(/\./, "_");
              }

              # extract key+value
              split($0, pair, /=/);
              key = pair[1];
              value = pair[2];
              
              # store into arrays
              if(jail == "any") {
                 any[key] = value;
              }
              else {
                 j[jail][key] = value;
              }
          }

          END {
              output as shell code
              for (jail in j) {
                 for (key in j[jail]) {
                    gsub(/\$name/, jail, j[jail][key])
                    printf "s_%s=%s\n", jail, key, j[jail][key]
                 }
                 for (anykey in any) {
                    if (! (jail, anykey) in j) {
                       gsub(/\$name/, jail, any[anykey])
                       printf "%s_%s=%s\n", jail, anykey, any[anykey]
                    }
                 }
              }
          }'
}

parse $1
