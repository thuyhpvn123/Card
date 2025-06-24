// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
struct MiningCode {
    bytes publicKey;          // Public key (32 bytes)
    uint256 boostRate;        // Mining boost rate
    uint256 maxDuration;      // Maximum valid duration
    CodeStatus status;        // Current status of the code
    address assignedTo;       // Address that owns the code
    address referrer;         // Address of the referrer
    uint256 referralReward;   // Reward for the referrer
    bool transferable;        // Whether the code is transferable
    uint256 lockUntil;        // Lock timestampưe
    LockType lockType;        // Type of lock
    uint256 expireTime;       //max time to activate code
}
enum CodeStatus { Pending, Approved, Actived, Expired }
enum LockType { None, ActiveLock, MiningLock, TransferLock }
struct BalanceUser {
    address device;
    uint256 balance;
    bool isCodeDevice; 
}