/* StartWindow.vala
 *
 * Copyright (C) 2018 MrSyabro
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gtk;

namespace CraftUniverse {
	[GtkTemplate (ui="/org/gnome/CraftUniverse/res/StarterWindow.ui")]
	class StarterWindow : ApplicationWindow {
		[GtkChild]ProgressBar progress_bar;

		public StarterWindow (Gtk.Application app) {
			set_application(app);
			set_icon(new Gdk.Pixbuf.from_resource("/org/gnome/CraftUniverse/res/icon.png"));
		}

		public void start_game(Build _build) {
			show_all();

			MainLoop update_build_ml = new MainLoop();
			update_files.begin(_build, (obj, res) => {
				update_files.end(res);
				update_build_ml.quit();
				info("End of update");
				close();
			});
			update_build_ml.run();
		}

		async void update_files(Build build) {
			try{
				// Загрузка библиотек
				info("Checking libraries list");
				Json.Parser parser = new Json.Parser();
				progress_bar.set_text("Проверка библиотек");
				File libraries_json_list = File.new_for_uri(@"$(Launcher.settings.site)libraries/$(build.gameVer)$(sizeof(void*)==8 ? "64" : "32").json");
				DataInputStream ljl_stream = new DataInputStream(yield libraries_json_list.read_async());
				parser.load_from_data(yield ljl_stream.read_upto_async ("\0", 1, Priority.DEFAULT, null, null));
				Json.Reader reader = new Json.Reader(parser.get_root());
				int ss = reader.count_members();
				double step = 1F / ss;
				double cp = 0F;
				int cs = 0;
				foreach(string lib in reader.list_members()) {
					reader.read_member(lib); string lib_hash = reader.get_string_value(); reader.end_member();
					File local_lib_file = File.new_for_path(Launcher.settings.Dir + Launcher.settings.lDir + "libraries/" + lib);
					if (!local_lib_file.query_exists() || (lib_hash != yield hash_sum(local_lib_file))){
						if (local_lib_file.query_exists()) warning("Bad hash, downloading: " + lib);
						progress_bar.set_text(lib);
						File server_lib_file = File.new_for_uri(Launcher.settings.site + "libraries/" + lib);
						yield server_lib_file.copy_async(local_lib_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, (current_num_bytes, total_num_bytes) => {
							progress_bar.set_fraction(cp + step * (double)current_num_bytes / (double)total_num_bytes);
						});
					}
					cp = cp + step;
					progress_bar.set_fraction(cp);
					progress_bar.set_text(@"Проверка библиотек $(cs++)/$ss");
				}
				progress_bar.set_fraction(0);
			} catch (Error e) { error(@"$(e.code): $(e.message)"); }

			try{
				// Загрузка ресурсов игры
				info("Checking assets list");
				Soup.Session update_session = new Soup.Session();
				Soup.Request asset_request;
				//InputStream asset_is;
				progress_bar.set_text("Проверка ресурсов");
				Json.Parser parser = new Json.Parser();
				File assets_json_list = File.new_for_uri(@"$(Launcher.settings.site)assets/indexes/$(build.assets).json");
				var ind_dir = File.new_for_path(@"$(Launcher.settings.Dir)$(Launcher.settings.lDir)assets/indexes/");
				if (!ind_dir.query_exists()) ind_dir.make_directory_with_parents();
				yield assets_json_list.copy_async(File.new_for_path(@"$(Launcher.settings.Dir)$(Launcher.settings.lDir)assets/indexes/$(build.assets).json"), FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, null);
				DataInputStream ajl_stream = new DataInputStream(yield assets_json_list.read_async());
				parser.load_from_data(yield ajl_stream.read_upto_async("\0", 1, Priority.DEFAULT, null, null));
				Json.Reader reader = new Json.Reader(parser.get_root());
				reader.read_member("objects");
				int ss = reader.count_members();
				double step = 1F / ss;
				double cp = 0F;
				int cs = 0;
				foreach(string asset in reader.list_members()) {
					reader.read_member(asset);
					reader.read_member("hash"); string asset_hash = reader.get_string_value(); reader.end_member();
					reader.end_member();
					File local_asset_file = File.new_for_path(@"$(Launcher.settings.Dir)$(Launcher.settings.lDir)assets/objects/$(asset_hash.substring(0, 2))/$asset_hash");
					File asset_dir = File.new_for_path(@"$(Launcher.settings.Dir)$(Launcher.settings.lDir)assets/objects/$(asset_hash.substring(0, 2))/");
					if (!asset_dir.query_exists()) { asset_dir.make_directory_with_parents(); }
					if (!local_asset_file.query_exists() || (asset_hash != yield hash_sum(local_asset_file))){
						asset_request = update_session.request(@"$(Launcher.settings.site)assets/objects/$(asset_hash.substring(0, 2))/$asset_hash.asset");
						InputStream asset_is = yield asset_request.send_async(null);
						if (local_asset_file.query_exists()) { yield local_asset_file.delete_async(); warning(@"Bad hash, downloading: $asset"); }
						yield (yield local_asset_file.create_async(FileCreateFlags.REPLACE_DESTINATION)).splice_async(asset_is, OutputStreamSpliceFlags.CLOSE_SOURCE);
					}
					cp = cp + step;
					progress_bar.set_fraction(cp);
					progress_bar.set_text(@"Проверка ресурсов $(cs++)/$ss");
				}
				progress_bar.set_fraction(0);
			} catch (Error e) { error(@"$(e.code): $(e.message)"); }

			try {
				// Загрузка исполняемых файлов игры
				info("Checking client");
				Soup.Session update_session = new Soup.Session();
				File server_client_file;
				File local_client_file;
				File local_client_dir;
				Json.Parser parser = new Json.Parser();
				progress_bar.set_text("Проверка клиента");
				Soup.Message message = new Soup.Message ("POST", Launcher.settings.site + "versions/");
				message.set_request("application/json", Soup.MemoryUse.COPY, build.gameVer.data);
				DataInputStream client_files_is = new DataInputStream(yield update_session.send_async (message));
				parser.load_from_data(yield client_files_is.read_upto_async ("\0", 1, Priority.DEFAULT, null, null));
				Json.Reader reader = new Json.Reader(parser.get_root());
				string cf_hash;
				int ss = reader.count_members();
				double step = 1F / ss;
				double cp = 0F;
				int cs = 0;
				foreach(string cf in reader.list_members()) {
					reader.read_member(cf); cf_hash = reader.get_string_value(); reader.end_member();
					local_client_file = File.new_for_path(@"$(Launcher.settings.Dir)$(Launcher.settings.lDir)versions/$cf");
					if (!local_client_file.query_exists() || (cf_hash != yield hash_sum(local_client_file))){
						info(cf);
						if (local_client_file.query_exists()) warning("Bad hash, downloading: " + cf);
						server_client_file = File.new_for_uri(@"$(Launcher.settings.site)versions/$cf");
						local_client_dir = local_client_file.get_parent();
						if (!local_client_dir.query_exists()) local_client_dir.make_directory_with_parents();
						yield server_client_file.copy_async(local_client_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, (current_num_bytes, total_num_bytes) => {
							progress_bar.set_fraction(cp + (step * (double)current_num_bytes) / (double)total_num_bytes);
						});
					}
					cp = cp + step;
					progress_bar.set_fraction(cp);
					progress_bar.set_text(@"Загрузка клиента $(cs++)/$ss");
				}
				progress_bar.set_fraction(0);
			} catch (Error e) { error(@"$(e.code): $(e.message)"); }

			try {
				// Загрузка модов
			} catch (Error e) { error(@"$(e.code): $(e.message)"); }
		}

		private async string hash_sum(File file){
    		Checksum checksum = new Checksum (ChecksumType.SHA1);
			var stream = yield file.read_async();

			uint8 fbuf[128];
		   	size_t size;

		   	while ((size = stream.read (fbuf)) > 0){
			  	checksum.update (fbuf, size);
			}
		   	return checksum.get_string ();
		}
	}
}
