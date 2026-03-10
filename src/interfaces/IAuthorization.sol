// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IAuthorization {
   
    struct SignatureData {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
        uint256 chainId;
        uint256 expiry;
    }

    
    event SignatureUsed(address indexed signer, bytes32 indexed digest, uint256 nonce);

  
    event NonceIncremented(address indexed signer, uint256 newNonce);

   
    function verifySignature( bytes32 _digest, SignatureData calldata _sigData, address _expectedSigner) external returns (bool);

   
    function domainSeparator() external view returns (bytes32);

   
    function getNonce(address _signer) external view returns (uint256);

  
    function isDigestUsed(bytes32 _digest) external view returns (bool);

    function incrementNonce() external;
}
