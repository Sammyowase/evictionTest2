// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


library AresLib {
     error SignatureExpired();

     error InvalidSignature();

     error SignatureReplay();

     error InvalidChainId();

     error ReentrancyDetected();

     error InvalidMerkleProof();

     function createNonceKey(address _signer, uint256 _nonce) internal pure returns (bytes32) {
        return hashBytes(abi.encodePacked(_signer, _nonce));
    }

     function createDomainSeparator( string memory _name, string memory _version, uint256 _chainId, address _verifyingContract ) internal pure returns (bytes32) {
        return hashBytes(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes(_version)),
                _chainId,
                _verifyingContract
            )
        );
    }

     function hashProposal( uint256 _proposalId, address _target, uint256 _amount, bytes32 _dataHash, uint256 _nonce, uint256 _expiry) internal pure returns (bytes32) {
        return hashBytes(
            abi.encode(
                keccak256("Proposal(uint256 proposalId,address target,uint256 amount,bytes32 dataHash,uint256 nonce,uint256 expiry)"),
                _proposalId,
                _target,
                _amount,
                _dataHash,
                _nonce,
                _expiry
            )
        );
    }

     function verifyMerkleProof( bytes32 _root, bytes32 _leaf, bytes32[] calldata _proof ) internal pure returns (bool) {
        bytes32 computedHash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (computedHash < proofElement) {
                computedHash = hashBytes(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = hashBytes(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == _root;
    }

     function createMerkleLeaf( uint256 _index, address _recipient, uint256 _amount) internal pure returns (bytes32) {
        return hashBytes(abi.encodePacked(_index, _recipient, _amount));
    }

     function getSafeTimestamp() internal view returns (uint256) {
        uint256 timestamp = block.timestamp;
        require(timestamp > 0, "Invalid timestamp");
        return timestamp;
    }

     function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

     function enterGuard(uint256 _status) internal pure returns (bool) {
        if (_status == 2) {
            revert ReentrancyDetected();
        }
        return true;
    }

     function exitGuard() internal pure returns (uint256) {
        return 1;
    }

     function hashBytes(bytes memory _data) internal pure returns (bytes32 hash) {
        assembly {
            hash := keccak256(add(_data, 32), mload(_data))
        }
    }
}


abstract contract ReentrancyGuard {
    uint256 internal constant _NOT_ENTERED = 1;
    uint256 internal constant _ENTERED = 2;

    uint256 private _guardStatus;

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_guardStatus == _ENTERED) {
            revert AresLib.ReentrancyDetected();
        }
        _guardStatus = _ENTERED;
    }

    function _nonReentrantAfter() internal {
        _guardStatus = _NOT_ENTERED;
    }

    function _getGuardStatus() internal view returns (uint256) {
        return _guardStatus;
    }

    function _setGuardStatus(uint256 _status) internal {
        _guardStatus = _status;
    }
}
