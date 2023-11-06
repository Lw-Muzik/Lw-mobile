package x.a.zix;

import java.io.File;

public class DeleteManager {
//        public static void main(String[] args) {
//            String folderPath = "/sdcard/myfolder"; // Replace with the actual folder path you want to delete
//
//            File folder = new File(folderPath);
//
//            if (folder.exists() && folder.isDirectory()) {
//                // Use a recursive method to delete the folder and its contents
//                if (deleteFolder(folder)) {
//                    System.out.println("Folder deleted successfully.");
//                } else {
//                    System.err.println("Failed to delete the folder.");
//                }
//            } else {
//                System.err.println("Folder does not exist or is not a directory.");
//            }
//        }

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
