import 'package:path/path.dart' as p;

class PortableBackupPathPolicy {
  const PortableBackupPathPolicy._();

  static String? resolveAttachmentPath({
    required String archiveEntryName,
    required String stagedAttachmentsPath,
  }) {
    final attachmentPrefix = 'attachments${p.separator}';
    if (!archiveEntryName.startsWith(attachmentPrefix)) return null;

    final relativeAttachment = archiveEntryName.substring(attachmentPrefix.length);
    if (relativeAttachment.isEmpty) {
      throw const FormatException('مسار مرفق غير صالح داخل النسخة');
    }

    final stagedRoot = p.normalize(stagedAttachmentsPath);
    final target = p.normalize(p.join(stagedRoot, relativeAttachment));
    if (!p.isWithin(stagedRoot, target)) {
      throw const FormatException('مسار مرفق غير آمن داخل النسخة');
    }
    return target;
  }
}

