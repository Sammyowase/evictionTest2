// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAuthorization} from "../interfaces/IAuthorization.sol";
import {AresLib} from "../libraries/AresLib.sol";


contract AuthorizationModule is IAuthorization {
    bytes32 private immutable _INITIAL_DOMAIN_SEPARATOR;
    uint256 private immutable _INITIAL_CHAIN_ID;

    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("ARES Authorization");
    bytes32 private constant _VERSION_HASH = keccak256("1.0.0");

    mapping(address => uint256) public nonces;

    mapping(bytes32 => bool) public usedDigests;

    uint256 public constant NONCE_COOLDOWN = 1;

    mapping(address => uint256) public lastNonceIncrement;

    constructor() {
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    function verifySignature( bytes32 _structHash, SignatureData calldata _sigData, address _expectedSigner ) external returns (bool) {
        if (block.timestamp > _sigData.expiry) {
            revert AresLib.SignatureExpired();
        }

        if (_sigData.chainId != block.chainid) {
            revert AresLib.InvalidChainId();
        }

        if (_sigData.nonce != nonces[_expectedSigner]) {
            revert AresLib.SignatureReplay();
        }

        bytes32 digest = _computeDigest(_structHash);

        if (usedDigests[digest]) {
            revert AresLib.SignatureReplay();
        }

        address recovered = ecrecover(digest, _sigData.v, _sigData.r, _sigData.s);

        if (recovered == address(0) || recovered != _expectedSigner) {
            revert AresLib.InvalidSignature();
        }

        usedDigests[digest] = true;
        nonces[_expectedSigner] = _sigData.nonce + 1;

        emit SignatureUsed(_expectedSigner, digest, _sigData.nonce);

        return true;
    }

    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _INITIAL_CHAIN_ID) {
            return _INITIAL_DOMAIN_SEPARATOR;
        }
        return _buildDomainSeparator();
    }

    function getNonce(address _signer) external view returns (uint256) {
        return nonces[_signer];
    }

    function isDigestUsed(bytes32 _digest) external view returns (bool) {
        return usedDigests[_digest];
    }

    function incrementNonce() external {
        if (block.number - lastNonceIncrement[msg.sender] < NONCE_COOLDOWN) {
            revert("Nonce increment cooldown active");
        }

        nonces[msg.sender]++;
        lastNonceIncrement[msg.sender] = block.number;

        emit NonceIncremented(msg.sender, nonces[msg.sender]);
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        return AresLib.hashBytes(
            abi.encode(
                _DOMAIN_TYPEHASH,
                _NAME_HASH,
                _VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    function _computeDigest(bytes32 _structHash) internal view returns (bytes32) {
        return AresLib.hashBytes(abi.encodePacked("\x19\x01", domainSeparator(), _structHash));
    }
}
