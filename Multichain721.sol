// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC721} from "./ERC721.sol";

abstract contract DemoERC721 is ERC721 {
    uint256 public chainPrefix;

    constructor () {
        chainPrefix = block.chainid;
        chainPrefix <<= 128;
    }

    function claim(uint128 seed) public returns (uint256 globalTokenId) {
        globalTokenId = chainPrefix + seed;
        require(!_exists(globalTokenId));
        _mint(msg.sender, globalTokenId);
    }

    function localId(uint256 globalId) public view returns (uint256 localId) {
        localId = globalId - chainPrefix;
    }
}

abstract contract DemoERC721WithState is DemoERC721 {
    struct State {
        uint256 foo;
        uint256 bar;
    }

    mapping(uint256 => State) public states;

    function setState(uint256 tokenId, uint256 foo, uint256 bar) public {
        require(ownerOf(tokenId) == msg.sender);
        states[tokenId] = State(foo, bar);
    }
}

interface Anycall {
    function anyCall(address[] memory to,bytes[] memory data,address[] memory fallbacks,uint256[] memory nonces,uint256 toChainID) external;
}

contract DemoMultiChain721WithState is DemoERC721WithState {
    address public anycall;

    address public admin;

    modifier onlyAnyCall() {
        require(msg.sender == anycall);
        _;
    }

    constructor(string memory name, string memory symbol, address _anycall, address _admin) ERC721(name, symbol) {
        anycall = _anycall;
        admin = _admin;
    }

    mapping(uint256 => address) public partnerTokens;

    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }

    function setPartnerTokens(uint256[] calldata chainIds, address[] calldata tokens) external onlyAdmin {
        for (uint8 i = 0; i < chainIds.length; i++) {
            partnerTokens[chainIds[i]] = tokens[i];
        }
    }

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
        //require(toChainId != block.chainid);

        // state is not changable after burn
        _burn(tokenId);

        // snapshot token state
        bytes memory state = abi.encode(states[tokenId].foo, states[tokenId].bar);

        // record nonce
        outboundArgs[outboundNonce] = OutboundArg(msg.sender, tokenId, states[tokenId]);
        outboundNonce++;

        // call anycall
        bytes memory data = abi.encodeWithSignature("inbound(uint256,address,bytes,uint256)", tokenId, receiver, state, toChainId);

        address[] memory to = new address[](1);
        to[0] = partnerTokens[toChainId];
        bytes[] memory datas = new bytes[](1);
        datas[0] = data;
        address[] memory fallbacks = new address[](1);
        fallbacks[0] = address(this);
        uint256[] memory nonces = new uint256[](1);
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