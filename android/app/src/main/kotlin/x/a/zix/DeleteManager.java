package x.a.zix;

import java.io.File;

public class DeleteManager {
       public static boolean deleteFolder(File folder) {
            if (folder.isDirectory()) {
                File[] files = folder.listFiles();
                if (files != null) {
                    for (File file : files) {
                        if (file.isDirectory()) {
                            // Recursive call to delete subfolders
                            if (!deleteFolder(file)) {
                                return false;
                            }
                        } else {
                            // Delete individual files
                            if (!file.delete()) {
                                return false;
                            }
                        }
                    }
                }
            }

            // Finally, delete the folder itself
            return folder.delete();
        }

}
