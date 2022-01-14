// SPDX-License-Identifier: MIT

import {ERC721} from "./ERC721.sol";

pragma solidity ^0.8.0;

abstract contract DemoERC721WithState is ERC721 {
    struct Profile {
        uint256 foo;
        uint256 bar;
    }

    mapping(uint256 => Profile) public profile;

    function setProfile(uint256 tokenId, uint256 foo, uint256 bar) public {
        require(ownerOf(tokenId) == msg.sender);
        profile[tokenId] = Profile(foo, bar);
    }
}

interface Anycall {
    function anyCall(address[] memory to,bytes[] memory data,address[] memory callbacks,uint256[] memory nonces,uint256 toChainID) external;
}

contract DemoMultiChain721WithState is DemoERC721WithState {
    address public anycall;

    address public lockAddress = address(0);

    modifier onlyAnyCall() {
        require(msg.sender == anycall);
        _;
    }

    constructor(string memory name, string memory symbol, address _anycall) ERC721(name, symbol) {
        anycall = _anycall;
    }

    mapping(uint256 => address) public branchToken;

    event LogOutbound(uint256 tokenId, address receiver, uint256 toChainId);
    event LogInbound(uint256 tokenId, address receiver, uint256 fromChainId);

    function outbound(uint256 tokenId, address receiver, uint256 toChainId) public {
        // pack token state
        bytes memory state = abi.encode(profile[tokenId].foo, profile[tokenId].bar);
        // lock or burn
        _burn(tokenId);

        // call anycall
        bytes memory data = abi.encodeWithSignature("inbound(uint256,address,bytes,uint256)", tokenId, receiver, state, toChainId);
        address[] memory to;
        to[0] = branchToken[toChainId];
        bytes[] memory datas;
        datas[0] = data;
        address[] memory callbacks;
        uint256[] memory nonces;
        Anycall(anycall).anyCall(to, datas, callbacks, nonces, toChainId);

        emit LogOutbound(tokenId, receiver, toChainId);

        return;
    }

    function inbound(uint256 tokenId, address receiver, bytes memory state, uint256 fromChainId) public {
        // unpack token stsate
        (uint256 foo, uint256 bar) = abi.decode(state, (uint256, uint256));
        profile[tokenId] = Profile(foo, bar);

        // unlock or mint and sync profile
        require(!_exists(tokenId));
        _mint(receiver, tokenId);

        emit LogInbound(tokenId, receiver, fromChainId);

        return;
    }
}
