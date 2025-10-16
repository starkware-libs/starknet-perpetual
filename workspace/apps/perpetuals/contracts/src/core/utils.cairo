use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::signature::stark::{HashType, PublicKey, Signature, validate_stark_signature};

pub fn validate_signature<T, +Drop<T>, +Copy<T>, +OffchainMessageHash<T>>(
    public_key: PublicKey, message: T, signature: Signature,
) -> HashType {
    let msg_hash = message.get_message_hash(:public_key);
    validate_stark_signature(:public_key, :msg_hash, :signature);
    msg_hash
}
