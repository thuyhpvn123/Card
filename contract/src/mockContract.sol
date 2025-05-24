// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Mock contract for PublicKeyFromPrivateKey
contract PublicKeyFromPrivateKeyMock  {
   function getPublicKeyFromPrivate(bytes memory _privateKey) external pure returns (bytes32) {
        // Mock implementation: Return a deterministic result based on the hash of the private key
        return keccak256(abi.encodePacked("public", _privateKey));
    }
}

contract MockCode {
    function activateCode(uint256 indexCode) external returns (uint256 boostRate, uint256 maxDuration, uint256 expireTime) {
        // Mock implementation that returns predefined values
        return (100*indexCode, 30 days+indexCode, block.timestamp + 365 days+indexCode);
    }
}
