//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
 
contract BlindBox is Ownable, ERC1155, Pausable {
    string public name;
    string public symbol;
    string public baseURL;
    
    mapping(address => bool) public minters;
    modifier onlyMinter() {
        require(minters[_msgSender()], "Mint: caller is not the minter");
        _;
    }
 
    struct Box { // ä�нṹ��
        uint    id;  // id��
        string  name;  // ����
        uint256 mintNum;  // mint��������ä�з�����
        uint256 openNum;  // open����������������
        uint256 totalSupply;  //����ä������
    }
 
    // id�ŵ�ä�е�ӳ��
    mapping(uint => Box) public boxMap;
 
    // ���캯��
    constructor(string memory url_) ERC1155(url_) {
        name = "Slime Blind Box";
        symbol = "SBOX";
        baseURL = url_;
        minters[_msgSender()] = true;
    }
 
    // �½�ä���ֻࣺ��owner���Դ���
    function newBox(uint boxID_, string memory name_, uint256 totalSupply_) public onlyOwner {
        require(boxID_ > 0 && boxMap[boxID_].id == 0, "box id invalid");
        boxMap[boxID_] = Box({
            id: boxID_,
            name: name_,
            mintNum: 0, // ��ʼΪ0
            openNum: 0, // ��ʼΪ0
            totalSupply: totalSupply_
        });
    }
 
    // �޸�ä���������
    function updateBox(uint boxID_, string memory name_, uint256 totalSupply_) public onlyOwner {
        require(boxID_ > 0 && boxMap[boxID_].id == boxID_, "id invalid");
        require(totalSupply_ >= boxMap[boxID_].mintNum, "totalSupply err");
 
        boxMap[boxID_] = Box({
            id: boxID_,
            name: name_,
            mintNum: boxMap[boxID_].mintNum,
            openNum: boxMap[boxID_].openNum,
            totalSupply: totalSupply_
        });
    }
    
    // ���쵥��ä��
    function mint(address to_, uint boxID_, uint num_) public onlyMinter whenNotPaused returns (bool) {
        require(num_ > 0, "mint number err");
        require(boxMap[boxID_].id != 0, "box id err");
        require(boxMap[boxID_].totalSupply >= boxMap[boxID_].mintNum + num_, "mint number is insufficient");
 
        boxMap[boxID_].mintNum += num_;
        _mint(to_, boxID_, num_, "");
        return true;
    }
 
    // ������ä��
    function mintBatch(address to_, uint[] memory boxIDs_, uint256[] memory nums_) public onlyMinter whenNotPaused returns (bool) {
        require(boxIDs_.length == nums_.length, "array length unequal");
 
        for (uint i = 0; i < boxIDs_.length; i++) {
            require(boxMap[boxIDs_[i]].id != 0, "box id err");
            require(boxMap[boxIDs_[i]].totalSupply >= boxMap[boxIDs_[i]].mintNum + nums_[i], "mint number is insufficient");
            boxMap[boxIDs_[i]].mintNum += nums_[i];
        }
 
        _mintBatch(to_, boxIDs_, nums_, "");
        return true;
    }
    
    // ������ä��
    function burn(address from_, uint boxID_, uint256 num_) public whenNotPaused {
        require(_msgSender() == from_ || isApprovedForAll(from_, _msgSender()), "burn caller is not owner nor approved");
        boxMap[boxID_].openNum += num_;
        _burn(from_, boxID_, num_);
    }
    
    // �����ä��
    function burnBatch(address from_, uint[] memory boxIDs_, uint256[] memory nums_) public whenNotPaused {
        require(_msgSender() == from_ || isApprovedForAll(from_, _msgSender()), "burn caller is not owner nor approved");
        require(boxIDs_.length == nums_.length, "array length unequal");
        for (uint i = 0; i < boxIDs_.length; i++) {
            boxMap[boxIDs_[i]].openNum += nums_[i];
        }
        _burnBatch(from_, boxIDs_, nums_);
    }
    
    // Ȩ�޹������ù���Ա��ɫ�������ж��ˣ���owner����
    function setMinter(address newMinter, bool power) public onlyOwner {
        minters[newMinter] = power;
    }
 
    function boxURL(uint boxID_) public view returns (string memory) {
        require(boxMap[boxID_].id != 0, "box not exist");
        return string(abi.encodePacked(baseURL, boxID_));
    }
 
    function setURL(string memory newURL_) public onlyOwner {
        baseURL = newURL_;
    }
 
    function setPause(bool isPause) public onlyOwner {
        if (isPause) {
            _pause();
        } else {
            _unpause();
        }
    }
}