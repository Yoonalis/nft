// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./721test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
 
contract AzureMarket is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _offerIds;
    /*
     * England拍卖模式 -> owner设置较低初始起拍价格，竞拍者逐步提高价格发起offer，价高者得    (* Default *) 
     * Netherlands拍卖模式 -> owner按价格预期设置起拍价格，竞拍者给出满足及以下的offer，直到有双方满意的价格
     * Simple定价模式 -> owner设置初始价格，出价者任意给offer，或通过SimpleBuyNFT()按当前最高标价购买
     */
    enum AuctionsType {England, Netherlands, Simple}  
    enum OfferStatus {available, fulfilled, cancelled} 
 
    mapping (uint => _Offer[]) private tokenIdToOffers;
    mapping (uint => uint) private tokenIdToBestPrice;
    mapping (address => uint) private userFunds;
    mapping (uint => AuctionsType) private tokenIdToAuctionsType;
    mapping (uint => uint) private OfferIdToTokenId;
    mapping (uint => address) private ownerOfThisNFT;
	
    Azure azure;
  
    struct _Offer {
        uint offerId;  
        uint id;       
        address user; 
        uint price;    
        OfferStatus offerstatus;
    }
 
    event Offer(
        uint offerId,
        uint id,
        address user,
        uint price,
        OfferStatus offerstatus
    );
 
    event OfferFilled(uint offerId, uint id, address newOwner);
    event OfferCancelled(uint offerId, uint id, address owner);
    event ClaimFunds(address user, uint amount);
 
    constructor(address _azure) {
        azure = Azure(_azure);
    }
 
    modifier onlyOwnerOf(uint _NFTid){
        address ownerOfNFT =  ownerOfThisNFT[_NFTid];
        require(msg.sender == ownerOfNFT);
        _;
    }
 
    /**
     * 用户通过向市场合约transfer指定ID的NFT资产，进入市场
     * _id 进入市场的NFT资产ID号
     * _price owner设定的初始价格
     * _typeNum 拍卖类型
     * 使用ownerOfThisNFT记录资产的owner
     */
    function addNFTToSellList(uint _id, uint _price, uint _typeNum) public {
        address ownerOfNFT =  azure.ownerOf(_id);
        require(msg.sender == ownerOfNFT);
		
        azure.transferFrom(msg.sender, address(this), _id); 
        if(_typeNum == 0){
            tokenIdToAuctionsType[_id] = AuctionsType.England;
        }else if(_typeNum == 1){
            tokenIdToAuctionsType[_id] = AuctionsType.Netherlands;
        }else{
            tokenIdToAuctionsType[_id] = AuctionsType.Simple;
        }
        tokenIdToBestPrice[_id] = _price;
		
        ownerOfThisNFT[_id] = msg.sender;
  }
 
    /**
     * 用户将市场中自己的NFT提取出来，转到自己账号
     * id 提取NFT资产的id号
     */
    function withdrawNFTFromSellList(uint _id) public onlyOwnerOf(_id){
        azure.transferFrom(address(this), msg.sender, _id);
    }
 
    /**
     * Netherlands模式，NFT拥有者主动降低价格
     * 设定的新价格不得比BestPrice价高
     * id 设定价格的NFT资产号
     * price 新价格
     */
    function decreasePriceForNetherlandsAuctionsType(uint _id,  uint _price) public onlyOwnerOf(_id){
        AuctionsType _auctionsType = tokenIdToAuctionsType[_id];
        require(_auctionsType == AuctionsType.Netherlands);
        uint  _currentBestPrice = tokenIdToBestPrice[_id];
        require(
            _price <= _currentBestPrice, 
            'The new price should be lesser than current best price given by owner of nft'
        );
        tokenIdToBestPrice[_id] = _price;
    }
 
    /**
     * Simple模式，NFT拥有者主动调低价格
     * id 设定价格的NFT资产id号
     * price 新价格
     */
    function changePriceForSimpleAuctionsType(uint _id,  uint _price) public onlyOwnerOf(_id){
        AuctionsType _auctionsType = tokenIdToAuctionsType[_id];
        require(_auctionsType == AuctionsType.Simple);
        tokenIdToBestPrice[_id] = _price;
    }
 
    /**
     * 用户提供offer并进入市场，用户通过提供eth付费进入市场
     * 检查eth额度
     * England模式 -> 提供的价格必须比BestPrice高
     * Netherlands模式 -> 提供的价格必须比BestPrice低
     * 将新的offer加入tokenIdToOffers列表
     * _id 目标NFT的ID号
     * _price 出价
     */
    function makeOffer(uint _id, uint _price) public payable{
        require(msg.value == _price, "The ETH amount should match with the offer Price");
		
        uint  _currentBestPrice = tokenIdToBestPrice[_id];
        AuctionsType _auctionsType = tokenIdToAuctionsType[_id];
		
        if(_auctionsType == AuctionsType.England){
            require(
                _price > _currentBestPrice, 
                'The new price should be largger than current best price for AuctionsType.England'
            );
            tokenIdToBestPrice[_id] = _price;
        }else if(_auctionsType == AuctionsType.Netherlands){
            require(
                _price <= _currentBestPrice, 
                'The new price should be lesser than/equal to current best price for AuctionsType.Netherlands'
            );
        }
		
        _Offer[] storage offersOfId = tokenIdToOffers[_id];
        _offerIds.increment();                           
        uint256 newOfferId = _offerIds.current();       
        offersOfId[offersOfId.length] = _Offer(newOfferId, _id, msg.sender, _price, OfferStatus.available);
        tokenIdToOffers[_id] = offersOfId;
        OfferIdToTokenId[newOfferId] = _id;
 
        emit Offer(newOfferId, _id, msg.sender, _price, OfferStatus.available);    
  }
 
    /**
     * 用户提供offer进入市场，用户通过合约内的eth资金余额付款进入市场
     * 检查eth余额，新的余额是减去出价后的额度
     * England模式 -> 提供的价格必须比BestPrice高
     * Netherlands模式 -> 提供的价格必须比BestPrice低
     * _id 目标NFT的ID号
     * _price 出价
     */
    function makeOfferWithUserFunds(uint _id, uint _price) public {
        require(userFunds[msg.sender] >= _price, 'The ETH amount should match with the offer Price');
		
        uint newbalance = userFunds[msg.sender] - _price; 
        userFunds[msg.sender] = newbalance; 
 
        uint  _currentBestPrice = tokenIdToBestPrice[_id];
        AuctionsType _auctionsType = tokenIdToAuctionsType[_id];
		
        if(_auctionsType == AuctionsType.England){
            require(
                _price > _currentBestPrice, 
                'The new price should be largger than current best price for AuctionsType.England'
            );
            tokenIdToBestPrice[_id] = _price;
        }else if(_auctionsType == AuctionsType.Netherlands){
            require(
                _price <= _currentBestPrice, 
                'The new price should be lesser/equal to current best price for AuctionsType.Netherlands'
            );
        }
		
        _Offer[] storage offersOfId = tokenIdToOffers[_id];
        _offerIds.increment();                           
        uint256 newOfferId = _offerIds.current();        
        offersOfId[offersOfId.length] = _Offer(newOfferId, _id, msg.sender, _price, OfferStatus.available);
        tokenIdToOffers[_id] = offersOfId;
        OfferIdToTokenId[newOfferId] = _id;
 
        emit Offer(newOfferId, _id, msg.sender, _price, OfferStatus.available);
    }
 
    /**
     * NFT拥有者接受offer，完成交易
     * 取消所有给该NFT的offer
     * _offerId 出价offer的ID号
     * _tokenId 交易的NFT的ID号
     */
    function fillOfferByNFTOwner(uint _offerId, uint _tokenId) public onlyOwnerOf(_tokenId){
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        require(offersOfId.length > 0, 'No Offer exist');
		
        _Offer memory currentOffer = _Offer(0, 0, address(0), 0, OfferStatus.available);
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            if(offerIndex.offerId == _offerId){
                currentOffer = offersOfId[index];
                break;
            }
        }
		
        require(currentOffer.offerId == _offerId, 'The offer must exist');
        require(currentOffer.offerstatus == OfferStatus.available, 'Offer status should be available');
 
        azure.transferFrom(address(this), currentOffer.user, currentOffer.id);   
 
        currentOffer.offerstatus = OfferStatus.fulfilled;        
        address ownerOfNFT =  ownerOfThisNFT[_tokenId];        
        userFunds[ownerOfNFT] += currentOffer.price;             
		
        //cancel other offers , refund or update userFunds.      
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            if(offerIndex.offerId != _offerId){
                offerIndex.offerstatus = OfferStatus.cancelled;
                userFunds[offerIndex.user] = offerIndex.price;
                emit OfferCancelled(offerIndex.offerId, offerIndex.id, offerIndex.user);
            }
        }
		
        emit OfferFilled(_offerId, currentOffer.id, currentOffer.user);
    }
 
    /**
     * 拒绝最高出价，并取消所有offer
     * _offerId 出价offer的ID号
     * _tokenId 交易的NFT的ID号
    */
    function rejectBestOfferAndCancelOtherOffers(uint _offerId, uint _tokenId) public  onlyOwnerOf(_tokenId){
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        require(offersOfId.length > 0, 'No Offer exist');
        _Offer memory currentOffer = _Offer(0, 0, address(0), 0, OfferStatus.available);
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            if(offerIndex.offerId == _offerId){
                currentOffer = offerIndex;
                break;
            }
        }
		
        require(currentOffer.offerId == _offerId, 'The offer must exist');
        require(currentOffer.offerstatus == OfferStatus.available, 'Offer status should be available');
		
        //cancel every offers , refund or update userFunds   
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            offerIndex.offerstatus = OfferStatus.cancelled;
            userFunds[offerIndex.user] = offerIndex.price;
            emit OfferCancelled(offerIndex.offerId, offerIndex.id, offerIndex.user);
        }
    }
	
    /**
     * 撤销自己的offer
     * _offerId 出价offer的ID号
     * _tokenId 交易的NFT的ID号
    */
    function cancelOwnOffer(uint _offerId, uint _tokenId) public {
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        require(offersOfId.length > 0, 'No Offer exist');
		
        _Offer memory currentOffer = _Offer(0, 0, address(0), 0, OfferStatus.available);
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            if(offerIndex.offerId == _offerId){
                currentOffer = offerIndex;
                break;
            }
        }
		
        require(msg.sender == currentOffer.user, 'msg.sender should be owner of this offer');
        require(currentOffer.offerId == _offerId, 'The offer must exist');
        require(currentOffer.offerstatus == OfferStatus.available, 'Offer status should be available');
		
        currentOffer.offerstatus = OfferStatus.cancelled;
        userFunds[currentOffer.user] = currentOffer.price;
		
        emit OfferCancelled(_offerId, currentOffer.id, msg.sender);
    }
 
    /*
     * Simple模式下直接按标价购买NFT，并取消所有给该NFT的offer
     * _tokenId 交易的NFT的ID号
    */
    function simpleBuyNFT(uint _tokenId) public payable{
        // 0.only for AuctionsType.Simple
        AuctionsType _auctionsType = tokenIdToAuctionsType[_tokenId];
        require(_auctionsType == AuctionsType.Simple);
		
        // 1.if new price match the best price
        uint  _currentBestPrice = tokenIdToBestPrice[_tokenId];
        require(msg.value == _currentBestPrice);
		
        // 2.transfer nft
        azure.transferFrom(address(this), msg.sender, _tokenId);
		
        // 3.update userFunds for nft owner
        address ownerOfNFT =  ownerOfThisNFT[_tokenId];
        userFunds[ownerOfNFT] += msg.value;
		
        // 4.cancel all other offers , refund or update userFunds  
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            offerIndex.offerstatus = OfferStatus.cancelled;
            userFunds[offerIndex.user] = offerIndex.price;
            emit OfferCancelled(offerIndex.offerId, _tokenId, offerIndex.user);
        }
    }
 
    /**
     * 取消所有给该NFT的offer，并取回自己的NFT
     * _tokenId 交易的NFT的ID号
    */
    function cancelAllOfferAndWithdrawFromSellList(uint _tokenId) public  onlyOwnerOf(_tokenId){
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
 
        azure.transferFrom(address(this), msg.sender, _tokenId);    
        //cancel every offers , refund or update userFunds              
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            offerIndex.offerstatus = OfferStatus.cancelled;
            userFunds[offerIndex.user] = offerIndex.price;
            emit OfferCancelled(offerIndex.offerId, _tokenId, offerIndex.user);
        }
    }
 
    /* 提取剩余eth资产 */
    function claimFunds() public {
        require(userFunds[msg.sender] > 0, "This user has no funds to be claimed");
        payable(msg.sender).transfer(userFunds[msg.sender]);
        userFunds[msg.sender] = 0; 
        emit ClaimFunds(msg.sender, userFunds[msg.sender]);   
    }
 
 
    /* request owner of nftid */
    function ownerOfNFTId(uint _NFTid)public view returns(address){
        address ownerOfNFT =  ownerOfThisNFT[_NFTid];
        return ownerOfNFT;
    }
 
    /* request NFT balance of owner */
    function NFTbalanceOf(address _owner) public view returns (uint256) {
        uint256 balance =  azure.balanceOf(_owner);
        return balance;
    }
 
    /* request nftid of owner at index i */
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256) {
        uint256 tokenid =  azure.tokenOfOwnerByIndex(_owner, _index);
        return tokenid;
    }
 
    /* request tokenURI of nftid */
    function tokenURIOfNFTId(uint _tokenId)public view returns(string memory){
        string memory tokenURI =  azure.tokenURI(_tokenId);
        return tokenURI;
    }
 
    /* request best price of nftid */
    function bestPriceOfNFTId(uint _tokenId)public view returns(uint256){
        uint  _currentBestPrice = tokenIdToBestPrice[_tokenId];
        return _currentBestPrice;
    }
 
    /* request all offers for nftid */
    function offersOfNFTId(uint _tokenId)public view returns(_Offer[] memory){
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        return offersOfId;
    }
	
    /* request offer detail of offer id */
    function offerDataOfOfferId(uint _Offerid)public view returns(_Offer memory){
        uint _tokenId = OfferIdToTokenId[_Offerid];
        _Offer[] memory offersOfId = tokenIdToOffers[_tokenId];
        require(offersOfId.length > 0,"No offers");
        for(uint index = 0; index < offersOfId.length; index++){
            _Offer memory offerIndex = offersOfId[index];
            if(offerIndex.offerId == _Offerid){
                return offerIndex;
            }
        }
        return _Offer(0, 0, address(0), 0, OfferStatus.available);
    }
 
    /* Fallback: reverts if Ether is sent to this smart-contract by mistake */
    fallback () external {
        revert();
    }
}