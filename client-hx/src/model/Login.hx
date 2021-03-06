package model;


class Login {
	
	public var commandType (default, null) : String;
	public var login(default, null) : model.Person;
	public var loginStatus(default, null) : String;
	public var nickName(default, null) : String;
	public function new (commandType : String, p: Person, s : LoginStatus){
		this.commandType = commandType;
		login = p;
		this.nickName = p.nickName;
		loginStatus = Std.string(s);
	}
	public static function createLoginResponse(incomingMessage : Dynamic, person : Person) : Login {
		//trace("Creating login response " + incomingMessage);
		var commandType : String = incomingMessage.commandType;
		var loginStatus : LoginStatus = Type.createEnum (LoginStatus, incomingMessage.loginStatus);
		var p : Dynamic = incomingMessage.login;
		var result : Login = new Login(commandType, person, loginStatus);
		return result;
	}
}