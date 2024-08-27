// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MonadBeasts is ERC721 {
    uint256 private _tokenIds;

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
            uint256 tokenId = _tokenIds;
            _mint(msg.sender, tokenId);

            _tokenIds += 1;
        }
    }
}
