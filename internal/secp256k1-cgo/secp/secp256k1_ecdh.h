#ifndef SECP256K1_ECDH_H
#define SECP256K1_ECDH_H

#include "secp256k1.h"

#ifdef __cplusplus
extern "C" {
#endif

/** A pointer to a function that hashes an EC point to obtain an ECDH secret
 *
 *  Returns: 1 if the point was successfully hashed.
 *           0 will cause my_secp256k1_ecdh to fail and return 0.
 *           Other return values are not allowed, and the behaviour of
 *           my_secp256k1_ecdh is undefined for other return values.
 *  Out:     output:     pointer to an array to be filled by the function
 *  In:      x32:        pointer to a 32-byte x coordinate
 *           y32:        pointer to a 32-byte y coordinate
 *           data:       arbitrary data pointer that is passed through
 */
typedef int (*my_secp256k1_ecdh_hash_function)(
  unsigned char *output,
  const unsigned char *x32,
  const unsigned char *y32,
  void *data
);

/** An implementation of SHA256 hash function that applies to compressed public key.
 * Populates the output parameter with 32 bytes. */
SECP256K1_API const my_secp256k1_ecdh_hash_function my_secp256k1_ecdh_hash_function_sha256;

/** A default ECDH hash function (currently equal to my_secp256k1_ecdh_hash_function_sha256).
 * Populates the output parameter with 32 bytes. */
SECP256K1_API const my_secp256k1_ecdh_hash_function my_secp256k1_ecdh_hash_function_default;

/** Compute an EC Diffie-Hellman secret in constant time
 *
 *  Returns: 1: exponentiation was successful
 *           0: scalar was invalid (zero or overflow) or hashfp returned 0
 *  Args:    ctx:        pointer to a context object.
 *  Out:     output:     pointer to an array to be filled by hashfp.
 *  In:      pubkey:     pointer to a my_secp256k1_pubkey containing an initialized public key.
 *           seckey:     a 32-byte scalar with which to multiply the point.
 *           hashfp:     pointer to a hash function. If NULL,
 *                       my_secp256k1_ecdh_hash_function_sha256 is used
 *                       (in which case, 32 bytes will be written to output).
 *           data:       arbitrary data pointer that is passed through to hashfp
 *                       (can be NULL for my_secp256k1_ecdh_hash_function_sha256).
 */
SECP256K1_API SECP256K1_WARN_UNUSED_RESULT int my_secp256k1_ecdh(
  const my_secp256k1_context *ctx,
  unsigned char *output,
  const my_secp256k1_pubkey *pubkey,
  const unsigned char *seckey,
  my_secp256k1_ecdh_hash_function hashfp,
  void *data
) SECP256K1_ARG_NONNULL(1) SECP256K1_ARG_NONNULL(2) SECP256K1_ARG_NONNULL(3) SECP256K1_ARG_NONNULL(4);

#ifdef __cplusplus
}
#endif

#endif /* SECP256K1_ECDH_H */
