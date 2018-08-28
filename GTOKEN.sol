pragma solidity 0.4.24;



/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (_a == 0) {
      return 0;
    }

    c = _a * _b;
    assert(c / _a == _b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
    // assert(_b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = _a / _b;
    // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold
    return _a / _b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    assert(_b <= _a);
    return _a - _b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
    c = _a + _b;
    assert(c >= _a);
    return c;
  }
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
  function totalSupply() public view returns (uint256);

  function balanceOf(address _who) public view returns (uint256);

  function allowance(address _owner, address _spender)
    public view returns (uint256);

  function transfer(address _to, uint256 _value) public returns (bool);

  function approve(address _spender, uint256 _value)
    public returns (bool);

  function transferFrom(address _from, address _to, uint256 _value)
    public returns (bool);

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value
  );

  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
}

contract GTOKEN is ERC20 {

	using SafeMath for uint256;

	string public constant name = "GTOKEN";
	string public constant symbol = "GTOKEN";
	uint8  public constant decimals = 18;


	//正式参数
	uint 	 constant FIRST_BATCH_UNLOCK_TIME = 2 * 24 * 3600;
	uint	 constant SECOND_BATCH_UNLOCK_TIME = 32 * 24 * 3600;
	uint	 constant THIRD_BATCH_UNLOCK_TIME = 62 * 24 * 3600;
	uint	 constant FOURTH_BATCH_UNLOCK_TIME = 92 * 24 * 3600;
	uint	 constant GENESIS_BATCH_UNLOCK_TIME = 180 * 24 * 3600;	
	uint	 constant MONTH_TIME_LEN = 2628000;	//一个月的秒数
	uint 	 constant YEAR_TIME_LEN = 12 * 2628000;

	//创世额度 10% 3亿代币
	uint 	 internal GENESIS_SUPPLY = 300000000 * 10 ** uint(decimals);
	//私募额度 40% 12亿代币
	uint   	 internal PRIVATE_SUPPLY = 1200000000 * 10 ** uint(decimals);
	//自由流通额度 50% 15亿代币
	uint	 internal FREEDOM_SUPPLY = 1500000000 * 10 ** uint(decimals);
	
	//交易所上线时间戳
	uint	 internal onlineTimeStamp = 0;

	//合约发布者
	address  internal owner;

	//创世余额
	mapping(address => uint256) internal genesis_balances;
	
	//解锁的创世额度
	mapping(address => uint256) internal unlock_genesis_balances;

	//私募额度余额
	mapping(address => uint256) internal private_balances;

	//解锁的私募额度
	mapping(address => uint256) internal unlock_private_balances;

	//自由流通余额
	mapping(address => uint256) internal balances;


	mapping (address => mapping (address => uint256)) internal allowed;

	uint256 internal totalSupply_ = 0;

	//为1时锁定整个系统，无法转账
	uint internal freezeSys = 0;
	 
	
	constructor() public {
		//记录合约发布者
		owner = msg.sender;
		//代币总量
	  	totalSupply_ = GENESIS_SUPPLY + PRIVATE_SUPPLY + FREEDOM_SUPPLY;
 
	  	genesis_balances[msg.sender] = GENESIS_SUPPLY;
		private_balances[msg.sender] = PRIVATE_SUPPLY;
		balances[msg.sender] = FREEDOM_SUPPLY;

	}

		/**
		* @dev Total number of tokens in existence
		*/
		function totalSupply() public view returns (uint256) {
			return totalSupply_;
		}

		/**
		* @dev Transfer token for a specified address
		* @param _to The address to transfer to.
		* @param _value The amount to be transferred.
		*/
		function transfer(address _to, uint256 _value) public returns (bool) {
			require(msg.data.length >= ( 2 * 32 ) + 4);
			//系统为解锁状态
			require(freezeSys == 0); 

			if( isTokenOnline() ) { //已上线交易所
					return transferOnlineStrategy(msg.sender,_to,_value);
			} 
			//线下交易
			return transferOfflineStrategy(msg.sender,_to,_value);
		}

		/**
		* @dev Gets the balance of the specified address.
		* @param _who The address to query the the balance of.
		* @return An uint256 representing the amount owned by the passed address.
		*/
		function balanceOf(address _who) public view returns(uint256) { 
				return balances[_who].add(
						private_balances[_who].sub(unlock_private_balances[_who])
					).add(
						genesis_balances[_who].sub(unlock_genesis_balances[_who])
					);
		}

		//用于测试的余额获取
		function transferableBalanceOf(address _who) public view returns(uint256) {

				if( isTokenOnline() ){
					//上交易所后，完整余额由自由额度，解锁的私募额度，解锁的创世额度组成
					return  balances[_who].add(currentUnlockPrivateBalance(_who)).add(currentUnlockGenesisBalance(_who));
				}
				//上交易所前 自由额度+私募额度锁定部分+创世额度锁定部分
				return balances[_who].add(private_balances[_who]);
		}

		function transferOnlineStrategy(address _from, address _to, uint256 _value) internal returns (bool) {
				require(_from != address(0));
				require(_to != address(0));

				//每次转账都尝试解锁锁定额度
				tryUnlockBalance();

				//余额不足
				require(balances[_from] >= _value);

				balances[_from] = balances[_from].sub(_value);
				balances[_to] = balances[_to].add(_value);

				emit Transfer(_from, _to, _value);
				return true;
		}

		function transferOfflineStrategy(address _from, address _to, uint256 _value) internal returns (bool) {
					//在上交易所前私募额度与自由额度均可转账
					require(
						_value <=  private_balances[_from].add(balances[_from])
					);
					require(_from != address(0));
					require(_to != address(0));

					uint256 priv_val = _value;
					uint256 free_val = 0;
					
					if( _value > private_balances[_from]){
							priv_val = private_balances[_from];
							free_val = _value.sub(priv_val);
					}

					//先发送私募额度，私募额度用光时，再发送自由额度
					private_balances[_from] = private_balances[_from].sub(priv_val);
					private_balances[_to] = private_balances[_to].add(priv_val);

					if( free_val != 0 ){
							balances[_from] = balances[_from].sub(free_val);
							balances[_to] = balances[_to].add(free_val);
					}

					emit Transfer(_from, _to, _value);
					return true;
		}

		function allowance(address _owner, address _spender) public view returns (uint256){
			return allowed[_owner][_spender];
		}

  		function transferFrom(address _from, address _to, uint256 _value) public returns (bool){
			 require(msg.data.length >= ( 3 * 32 ) + 4); 

			//系统为解锁状态
			require(freezeSys == 0); 

			//查看是否在发送者允许的转账范围内
			require(_value <= allowed[_from][msg.sender]);

			bool ret = false;
			if( isTokenOnline() ) { //已上线交易所
				ret = transferOnlineStrategy(_from,_to,_value);
			} else {
				//线下交易
				ret = transferOfflineStrategy(_from,_to,_value);
			}
			
			if( ret == true ){
				allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
			}

			return ret;
		}

  		function approve(address _spender, uint256 _value) public returns (bool){
  			allowed[msg.sender][_spender] = _value;
    		emit Approval(msg.sender, _spender, _value);
    		return true;
		}
 

		//创世额度分配
		function transferGenesis(address _to, uint256 _value) public returns(bool) {
				//分配创世额度只可合约创建者操作
				require(msg.sender == owner);
				//require(!isTokenOnline());

				require(_value <= genesis_balances[msg.sender]);
				require(_to != address(0));

				genesis_balances[msg.sender] = genesis_balances[msg.sender].sub(_value);
				genesis_balances[_to] = genesis_balances[_to].add(_value);
				emit Transfer(msg.sender, _to, _value);
				return true;
		}

		//每次转账尝试
		function tryUnlockBalance() internal {
				//需要在代币上交易所之后
				require(isTokenOnline());

				uint256 balanceInc = currentUnlockPrivateBalance(msg.sender);

				if( balanceInc != 0 ){//私募额度解锁
					unlock_private_balances[msg.sender] = unlock_private_balances[msg.sender].add(balanceInc);
					balances[msg.sender] = balances[msg.sender].add(balanceInc);
				}

				balanceInc = currentUnlockGenesisBalance(msg.sender);

				if( balanceInc != 0 ){//创世额度解锁
					unlock_genesis_balances[msg.sender] = unlock_genesis_balances[msg.sender].add(balanceInc);
					balances[msg.sender] = balances[msg.sender].add(balanceInc);
				}
		}


		//获取当前用户私募解锁额度
		function currentUnlockPrivateBalance(address _who) internal view returns(uint256) { 
				if(private_balances[_who] == 0)
					return 0;

				uint currTime = block.timestamp; 
				if( currTime >= onlineTimeStamp + FOURTH_BATCH_UNLOCK_TIME  ){
						//完全解锁
						return private_balances[_who].sub(unlock_private_balances[_who]);
				}else if( currTime >= onlineTimeStamp + THIRD_BATCH_UNLOCK_TIME ){
						//总共解锁了70%
						return private_balances[_who].mul(7).div(10).sub(unlock_private_balances[_who]);
				}else if( currTime >= onlineTimeStamp + SECOND_BATCH_UNLOCK_TIME){
						//总共解锁了50%
						return private_balances[_who].div(2).sub(unlock_private_balances[_who]);
				}else if( currTime >= onlineTimeStamp +  FIRST_BATCH_UNLOCK_TIME){
						//总共解锁30%
						return private_balances[_who].mul(3).div(10).sub(unlock_private_balances[_who]);
				} 
				return 0;
		}

		function currentUnlockGenesisBalance(address _who) internal view returns(uint256) { 
				if(genesis_balances[_who] == 0)
					return 0;

				uint currTime = block.timestamp;  
				if( currTime >= onlineTimeStamp + GENESIS_BATCH_UNLOCK_TIME ){
						
						uint t = currTime.sub(onlineTimeStamp).sub(GENESIS_BATCH_UNLOCK_TIME);
						uint m =  t.div(MONTH_TIME_LEN) + 1;

						if( m > 12 ){
								m = 12;
						}

						return genesis_balances[_who].mul(m).div(12).sub(unlock_genesis_balances[_who]);
				}
				//尚未到解锁时间
				return 0;
		}

		//设置系统锁定，0为解锁，1为锁定
		function setSystemFreeze(uint f) public {
			require(msg.sender == owner);
			freezeSys = f;
		}
 

		//查询系统是否被锁定
		function isSystemFreeze() public view returns(bool) {
			return freezeSys != 0;
		}
 
		//标记代币上交易所
		function setTokenOnline() public {
				//必须由合约拥有者调用
				require(msg.sender == owner);
				//全局只可设置一次！！！
				require(onlineTimeStamp == 0);
				onlineTimeStamp = block.timestamp;
		}

		//查询代币是否上交易所
		function isTokenOnline() public view returns(bool) {
				return (onlineTimeStamp != 0);
		}


}