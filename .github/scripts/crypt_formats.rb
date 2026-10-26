# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Prints what String#crypt returns for one setting of each hash format a
# Linux Ruby may meet, one per line as NAME<TAB>SETTING<TAB>RESULT, where
# RESULT is the hash or the error Ruby raised. replace-libcrypt.sh runs
# it as a built app's main.rb, with each libcrypt.so.2 it swaps in, and
# with the computer's own Ruby, to compare them.
FORMATS = {
  "DES" => "ab",
  "BSDi extended DES (_)" => "_J9..CCCC",
  "MD5 ($1$)" => "$1$saltsalt$",
  "SHA-256 ($5$)" => "$5$saltsalt$",
  "SHA-512 ($6$)" => "$6$saltsalt$",
  "bcrypt ($2b$)" => "$2b$05$CCCCCCCCCCCCCCCCCCCCC.",
  "bcrypt ($2y$)" => "$2y$05$CCCCCCCCCCCCCCCCCCCCC.",
  "yescrypt ($y$)" => "$y$j9T$saltsaltsaltsalt$",
  "gost-yescrypt ($gy$)" => "$gy$j9T$saltsaltsaltsalt$",
  "scrypt ($7$)" => "$7$CU..../....saltsaltsaltsalt$",
  "SHA-1 ($sha1$)" => "$sha1$248488$saltsaltsalt$",
  "SunMD5 ($md5)" => "$md5,rounds=5000$saltsalt$",
  "NT ($3$)" => "$3$",
}.freeze

FORMATS.each do |name, setting|
  result = begin
    "password".crypt(setting)
  rescue SystemCallError, ArgumentError => e
    "error: #{e.class}"
  end
  puts [name, setting, result].join("\t")
end
