// SPDX-License-Identifier: UNLICENSED
// NFT Contract 
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MonadBeasts is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    bytes32 public merkleRoot;

    //Must be called after creating a merkle tree from whitelist
    constructor(bytes32 merkleRoot_) ERC721("Monad Beasts", "MB") {
        merkleRoot = merkleRoot_;
    }

    function mint(uint256 quantity, bytes32[] calldata merkleProof) public {
        bytes32 node = keccak256(abi.encodePacked(msg.sender, quantity));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "invalid proof"
        );

        // Change the logic here if you need to work with rarity
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIds.current();
            _mint(msg.sender, tokenId);

            _tokenIds.increment();
        }
    }
}
