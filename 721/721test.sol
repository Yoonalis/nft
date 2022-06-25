// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// 引入Pausable，暂停控制抽象合约
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract Azure is Ownable, Pausable, ERC721, ERC721Enumerable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    using Strings  for uint256;

    string[] public tokenURIs;

    // Constants
    // 限定NFT数量
    uint256 public constant TOTALSUPPLY = 10000000;
    uint256 public constant BUY_PRICE = 0.02 ether;
    // 一次最多购买数量
	uint256 public constant MaxBuyAmount = 20;
 
    // Mappings
    mapping(string => bool) _tokenURIExists;
    // mapping(uint => string) _tokenIdToTokenURI;
    mapping(address => bool) private minters;
    // 从 token id 到 URI 的映射
    mapping(uint256 => string) private TokenURI;
 
    // Modifiers
    modifier onlyMinter() {
        require(minters[_msgSender()], "Mint: caller is not the minter");
        _;
    }
  
    Counters.Counter private currentTokenId;
    string private _tokenBaseURI;
    string private _tokenExtendURI;

    // 构造函数
    constructor() ERC721("Azure", "A") {
        minters[_msgSender()] = true;
    }

    // 铸造NFT
    function mint(address recipient) public onlyMinter whenNotPaused returns (uint256) {
        uint256 tokenId = currentTokenId.current();
        require(tokenId < TOTALSUPPLY, "Max supply reached");
 
        currentTokenId.increment();
        uint256 newItemId = currentTokenId.current();
        _safeMint(recipient, newItemId);
        return newItemId;
    }
 
    // 实现批量购买功能
    // 用户可以购买并 mint 新 NFT
    function buy(address recipient) public payable whenNotPaused returns (uint256) {       
        uint256 tokenId = currentTokenId.current();
        require(tokenId < TOTALSUPPLY, "Max supply reached");
        require(msg.value == BUY_PRICE, "Transaction value did not equal the buy price");
 
        currentTokenId.increment();
        uint256 newItemId = currentTokenId.current();
        _safeMint(recipient, newItemId);
        return newItemId;
    }

    // 批量购买 NFT
    function buy(address recipient, uint256 amount) public payable whenNotPaused returns (bool) {       
        uint256 tokenId = currentTokenId.current();
        require(amount >= 1 && amount <= MaxBuyAmount, "amount must between 1 and 20");
        require(tokenId + amount - 1 < TOTALSUPPLY, "Max supply reached");
        if (_msgSender() != owner()) {
            // 如果不是 owner，支付额度必须够
            require(msg.value >= BUY_PRICE * amount, "Transaction value did not equal the buy price");
        }
        // 通过循环进行批量 mint 操作
        for(uint256 i = 0; i < amount; i++){
            currentTokenId.increment();
            uint256 newItemId = currentTokenId.current();
            _safeMint(recipient, newItemId);
        }
        return true;
    }
 
    // 提取售卖NFT得到的ether         
    function withdraw(address payable payee) public onlyOwner {
        // payee.transfer(address(this).balance);
        (bool success, ) = payee.call{value: address(this).balance}("");
        require(success);
    }
 
    // 销毁NFT
    function burn(uint256 tokenId_) public whenNotPaused returns (bool) {
        require(
            _msgSender() == ownerOf(tokenId_) || 
            _msgSender() == getApproved(tokenId_) || 
            isApprovedForAll(ownerOf(tokenId_), _msgSender()), 
            "burn caller is not owner nor approved"
        );
        _burn(tokenId_);
		return true;
    }
 
    // 设置minter作为二级管理员：可以为多个，可以为合约地址
    function setMinter(address minter_, bool newState_) public onlyOwner {
        minters[minter_] = newState_;
    }
    function isMinter(address minter_) public view returns (bool){
        return minters[minter_];
    }
	
    // 设置指定 ID 的 URI
    function setURI(uint256 tokenId_, string memory tokenURI_) public {
        require(_exists(tokenId_), "ERC721Metadata: URI query for nonexistent token");
        // 仅 NFT 的拥有者或管理员可以进行操作
        require(
            _msgSender() == ownerOf(tokenId_) || minters[_msgSender()],
            "setURI caller is not owner nor minter"
        );
        // 通过映射保存 URI
        TokenURI[tokenId_] = tokenURI_;
    }

    // 返回指定 ID 的 URI
    function tokenURI(uint256 tokenId_) public view override returns (string memory) {
        require(_exists(tokenId_), "ERC721Metadata: URI query for nonexistent token");
        return TokenURI[tokenId_];
    }

    // 设置pause状态，仅owner有此权限
    function setPause(bool isPaused) public onlyOwner {
        if (isPaused) {
            _pause();
        } else {
            _unpause();
        }
    }

    // 继承ERC721Enumerable必须要实现的方法
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner) public view virtual override(ERC721, IERC721) returns (uint256) {
        return super.balanceOf(owner);
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        return super.tokenOfOwnerByIndex(owner, index);
    }

    // 铸造NFT
    function safeMint(string memory _tokenURI) public onlyMinter whenNotPaused returns (uint256) {
        require(!_tokenURIExists[_tokenURI], "The token URI should be unique");
        require(currentTokenId.current() < TOTALSUPPLY, "Max supply reached");

        currentTokenId.increment();
        tokenURIs.push(_tokenURI);
        uint256 newItemId = currentTokenId.current();
        TokenURI[newItemId] = _tokenURI;
        _tokenURIExists[_tokenURI] = true;

        _safeMint(msg.sender, newItemId);
        return newItemId;
    }
}
