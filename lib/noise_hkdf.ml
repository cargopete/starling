let hmac ~key data = Digestif.SHA256.(to_raw_string (hmac_string ~key data))

let hkdf2 ~ck ~ikm =
  let temp = hmac ~key:ck ikm in
  let out1 = hmac ~key:temp "\x01" in
  let out2 = hmac ~key:temp (out1 ^ "\x02") in
  (out1, out2)

let hkdf3 ~ck ~ikm =
  let temp = hmac ~key:ck ikm in
  let out1 = hmac ~key:temp "\x01" in
  let out2 = hmac ~key:temp (out1 ^ "\x02") in
  let out3 = hmac ~key:temp (out2 ^ "\x03") in
  (out1, out2, out3)
