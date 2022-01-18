// SPDX-License-Identifier: GPL-3.0-or-later

import {ERC721} from "./ERC721.sol";

pragma solidity ^0.8.0;

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

    mapping(uint256 => address) public branchTokens;

    event LogOutbound(uint256 tokenId, address receiver, uint256 toChainId);
    event LogInbound(uint256 tokenId, address receiver, uint256 fromChainId);
    event LogOutboundRevert(uint256 nonce, uint256 tokenId, address receiver);

    uint256 public outboundNonce = 0;
    struct OutboundArg {
        address owner;
        uint256 tokenId;
        State state;
    }
    mapping(uint256 => OutboundArg) public outboundArgs;

    function outbound(uint256 tokenId, address receiver, uint256 toChainId) public {
        require(ownerOf(tokenId) == msg.sender);

        // state is not changable after burn
        _burn(tokenId);

        // snapshot token state
        bytes memory state = abi.encode(states[tokenId].foo, states[tokenId].bar);

        // record nonce
        outboundArgs[outboundNonce] = OutboundArg(msg.sender, tokenId, states[tokenId]);
        outboundNonce++;

        // call anycall
        bytes memory data = abi.encodeWithSignature("inbound(uint256,address,bytes,uint256)", tokenId, receiver, state, toChainId);
        address[] memory to;
        to[0] = branchTokens[toChainId];
        bytes[] memory datas;
        datas[0] = data;
        address[] memory fallbacks;
        fallbacks[0] = address(this);
        uint256[] memory nonces;
        nonces[0] = outboundNonce;
        Anycall(anycall).anyCall(to, datas, fallbacks, nonces, toChainId);

        emit LogOutbound(tokenId, receiver, toChainId);

        return;
    }

    function anyCallFallback(uint256 nonce) public onlyAnyCall {
        // retrieve outbound args
        OutboundArg memory args = outboundArgs[nonce];
        require(!_exists(args.tokenId));
        _mint(args.owner, args.tokenId);
        states[args.tokenId] = args.state;
        outboundArgs[nonce] = OutboundArg(address(0), uint256(0), State(uint256(0), uint256(0)));
        emit LogOutboundRevert(nonce, args.tokenId, args.owner);
    }

    function inbound(uint256 tokenId, address receiver, bytes memory state, uint256 fromChainId) public onlyAnyCall {
        // unlock or mint and sync profile
        require(!_exists(tokenId));
        _mint(receiver, tokenId);

        // unpack token stsate
        (uint256 foo, uint256 bar) = abi.decode(state, (uint256, uint256));
        states[tokenId] = State(foo, bar);

        emit LogInbound(tokenId, receiver, fromChainId);

        return;
    }
}