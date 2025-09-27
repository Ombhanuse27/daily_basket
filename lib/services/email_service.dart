import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:intl/intl.dart';

class EmailService {
  static final String _username = '90797f002@smtp-brevo.com';
  static final String _password = 'KzvjCOs8pQq2RkNS';

  static final smtpServer = SmtpServer(
    'smtp-relay.brevo.com',
    port: 587,
    username: _username,
    password: _password,
  );

  /// 🔐 For Admins
  static Future<void> sendActivationEmail({
    required String toEmail,
    required String userName,
    required String activationKey,
    required DateTime expiryDate,
  }) async {
    final message = Message()
      ..from = Address(_username, 'DailyBasket Admin')
      ..recipients.add(toEmail)
      ..subject = 'Your DailyBasket Activation Key'
      ..text = '''
Hello $userName,

Your activation request has been approved. Below is your one-time activation key:

🔑 Activation Key: $activationKey
📅 Expires on: ${expiryDate.toLocal()}

Please enter this key in the DailyBasket app to activate your account.

Thank you,
DailyBasket Team
''';

    try {
      final sendReport = await send(message, smtpServer);
      print('✅ Activation email sent to admin: $sendReport');
    } catch (e) {
      print('❌ Failed to send admin activation email: $e');
    }
  }

  /// 🧑‍💼 For Employees
  static Future<void> sendEmployeeActivationEmail({
    required String toEmail,
    required String employeeName,
    required String password,
    required DateTime expiryDate,
  }) async {
    final String username = '90797f002@smtp-brevo.com'; // Brevo login
    final String passwordSMTP = 'KzvjCOs8pQq2RkNS';      // Brevo SMTP password

    final smtpServer = SmtpServer(
      'smtp-relay.brevo.com',
      port: 587,
      username: username,
      password: passwordSMTP,
      ssl: false,
      allowInsecure: false,
    );

    final message = Message()
      ..from = Address('naikamar1029@gmail.com', 'DailyBasket Admin')
      ..recipients.add(toEmail)
      ..subject = '✅ Your DailyBasket Employee Account Details'
      ..text = '''
Hello $employeeName,

Welcome to DailyBasket! 🎉

Here are your employee login details:

📧 Email: $toEmail  
🔐 Password: $password  
📅 Expiry Date: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(expiryDate)}

Please use these credentials to log in to the DailyBasket app before the expiry date.

Thank you,  
DailyBasket Team
''';

    try {
      await send(message, smtpServer);
      print("✅ Employee email sent to $toEmail");
    } catch (e) {
      print("❌ Failed to send email to $toEmail: $e");
    }
  }

}






