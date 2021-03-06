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
 
    struct Box { // 盲盒结构体
        uint    id;  // id号
        string  name;  // 名字
        uint256 mintNum;  // mint数量，即盲盒发放量
        uint256 openNum;  // open数量，即开盒数量
        uint256 totalSupply;  //该类盲盒总量
    }
 
    // id号到盲盒的映射
    mapping(uint => Box) public boxMap;
 
    // 构造函数
    constructor(string memory url_) ERC1155(url_) {
        name = "Slime Blind Box";
        symbol = "SBOX";
        baseURL = url_;
        minters[_msgSender()] = true;
    }
 
    // 新建盲盒类：只有owner可以创建
    function newBox(uint boxID_, string memory name_, uint256 totalSupply_) public onlyOwner {
        require(boxID_ > 0 && boxMap[boxID_].id == 0, "box id invalid");
        boxMap[boxID_] = Box({
            id: boxID_,
            name: name_,
            mintNum: 0, // 初始为0
            openNum: 0, // 初始为0
            totalSupply: totalSupply_
        });
    }
 
    // 修改盲盒类的属性
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
    
    // 铸造单个盲盒
    function mint(address to_, uint boxID_, uint num_) public onlyMinter whenNotPaused returns (bool) {
        require(num_ > 0, "mint number err");
        require(boxMap[boxID_].id != 0, "box id err");
        require(boxMap[boxID_].totalSupply >= boxMap[boxID_].mintNum + num_, "mint number is insufficient");
 
        boxMap[boxID_].mintNum += num_;
        _mint(to_, boxID_, num_, "");
        return true;
    }
 
    // 铸造多个盲盒
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
    
    // 开单个盲盒
    function burn(address from_, uint boxID_, uint256 num_) public whenNotPaused {
        require(_msgSender() == from_ || isApprovedForAll(from_, _msgSender()), "burn caller is not owner nor approved");
        boxMap[boxID_].openNum += num_;
        _burn(from_, boxID_, num_);
    }
    
    // 开多个盲盒
    function burnBatch(address from_, uint[] memory boxIDs_, uint256[] memory nums_) public whenNotPaused {
        require(_msgSender() == from_ || isApprovedForAll(from_, _msgSender()), "burn caller is not owner nor approved");
        require(boxIDs_.length == nums_.length, "array length unequal");
        for (uint i = 0; i < boxIDs_.length; i++) {
            boxMap[boxIDs_[i]].openNum += nums_[i];
        }
        _burnBatch(from_, boxIDs_, nums_);
    }
    
    // 权限管理：设置管理员角色，可以有多人，由owner设置
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