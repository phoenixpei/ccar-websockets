package model;

enum CommandType {
	Login;
	SendMessage;
	ManageUser;
	QueryUser;
	DeleteUser;
	UpdateUser;
	CreateUserTerms;
	UpdateUserTerms;
	QueryUserTerms;
	DeleteUserTerms;
	CreateUserPreferences;
	UpdateUserPreferences;
	QueryUserPreferences;
	DeleteUserPreferences;
	CCARUpload;
	ParsedCCARText;
	Undefined;
	UserJoined;
	UserLeft;
	UserLoggedIn;
	UserBanned;
}