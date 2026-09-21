# Guardian Auth runtime policy for a dedicated Transit mount.
# Rendered by configure-auth.sh with the mount path substituted for @TRANSIT_MOUNT@.
#
# The entire mount is allocated exclusively to Guardian Auth. A single-segment
# wildcard avoids accidentally granting key child operations. required_parameters
# closes the ACL's "no data fields" allowance: without it an empty or type-less
# create would provision Transit's default AES key under a name that Auth can
# then never replace. OpenBao applies required_parameters to reads too, so Auth
# declares `type=ecdsa-p256` as a query parameter on reads.
path "@TRANSIT_MOUNT@/keys/+" {
  capabilities = ["create", "read", "update"]
  required_parameters = ["type"]
  allowed_parameters = {
    "type" = ["ecdsa-p256"]
    "exportable" = [false]
    "allow_plaintext_backup" = [false]
    "derived" = [false]
    "auto_rotate_period" = ["0"]
  }
}
# key_version is required but unconstrained: the application pins the exact
# version on every request (Transit treats 0 as "latest").
path "@TRANSIT_MOUNT@/sign/+/sha2-256" {
  capabilities = ["update"]
  required_parameters = ["input", "key_version", "prehashed", "marshaling_algorithm"]
  allowed_parameters = {
    "input" = []
    "key_version" = []
    "prehashed" = [true]
    "marshaling_algorithm" = ["jws"]
  }
}

# Renew only the workload token used by this caller.
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# SigningHealth checks the caller's own permissions; the default policy is
# deliberately absent from workload tokens. This grants no other-token lookup.
path "sys/capabilities-self" {
  capabilities = ["update"]
}
