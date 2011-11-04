//
//  Copyright (C) 2011 Maxwell Barvian
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Maya {

    public static int main (string[] args) {

        var context = new OptionContext("Calendar");
        context.add_main_entries(Application.app_options, "maya");
        context.add_group(Gtk.get_option_group(true));

        try {
            context.parse(ref args);
        } catch(Error e) {
            print(e.message + "\n");
        }

        Gtk.init(ref args);

        return new Application ().run (args);
    }

	public class Application : Granite.Application {

		construct {

			// App info
			build_data_dir = Build.DATADIR;
			build_pkg_data_dir = Build.PKGDATADIR;
			build_release_name = Build.RELEASE_NAME;
			build_version = Build.VERSION;
			build_version_info = Build.VERSION_INFO;

			program_name = "Maya";
			exec_name = "maya";

			app_years = "2011";
			application_id = "net.launchpad.maya";
			app_icon = "office-calendar";
			app_launcher = "maya.desktop";

			main_url = "https://launchpad.net/maya";
			bug_url = "https://bugs.launchpad.net/maya";
			help_url = "https://answers.launchpad.net/maya";
			translate_url = "https://translations.launchpad.net/maya";

			about_authors = {
				"Maxwell Barvian <maxwell@elementaryos.org>",
				"Jaap Broekhuizen <jaapz.b@gmail.com>",
				"Avi Romanoff <aviromanoff@gmail.com>",
				"Allen Lowe <lallenlowe@gmail.com>"
			};
			about_documenters = {
				"Maxwell Barvian <maxwell@elementaryos.org>"
			};
			about_artists = {
				"Daniel Foré <bunny@go-docky.com>"
			};
			about_translators = "";
            about_license_type = Gtk.License.GPL_3_0;
		}

		private static bool APP_OPTION_ADD = false;

		public static const OptionEntry[] app_options = {
			{ "add-event", 'a', 0, OptionArg.NONE, out APP_OPTION_ADD, "Just show an add event dialog", null },
			{ null }
		};

		private Settings.SavedState saved_state { get; set; }
		private Settings.MayaSettings prefs { get; set; }

        private Gtk.Window window { get; set; }
		private View.MayaToolbar toolbar { get; set; }
		private View.Calendar.View calendar { get; set; }
		private View.Sidebar sidebar { get; set; }
        private Gtk.HPaned hpaned { get; set; }

		private Services.DateHandler handler { get; private set; }
	
		protected override void activate () {

			if (get_windows () != null) {
				get_windows ().data.present (); // present window if app is already running
			    return;
			}

			if (APP_OPTION_ADD) {
			    (new View.AddEventDialog.without_parent (this)).show_all ();
			} else {
                initialise();
			    window.show_all ();
			}
		}

        private void initialise() {

			toolbar = new View.MayaToolbar ();
			calendar = new View.Calendar.View ();
			sidebar = new View.Sidebar ();

            window = new Gtk.Window ();
			window.title = "Maya";
			window.icon_name = "office-calendar";
			window.set_size_request (700, 400);
            window.delete_event.connect (window_delete_event_cb);
            window.destroy.connect( () => Gtk.main_quit() );

			toolbar.button_add.clicked.connect(toolbutton_add_clicked);
			toolbar.menu.today.activate.connect ( () => set_date (null));
			toolbar.menu.fullscreen.toggled.connect (toggle_fullscreen);
			toolbar.menu.weeknumbers.toggled.connect (menu_show_weeks_toggled);

			toolbar.month_switcher.left_clicked.connect (() => handler.add_month_offset (-1));
			toolbar.month_switcher.right_clicked.connect (() => handler.add_month_offset (1));
			toolbar.year_switcher.left_clicked.connect (() => handler.add_year_offset (-1));
			toolbar.year_switcher.right_clicked.connect (() => handler.add_year_offset (1));

			var vbox = new Gtk.VBox (false, 0);
			hpaned = new Gtk.HPaned ();
			vbox.pack_start (toolbar, false, false, 0);
			vbox.pack_end (hpaned);
			hpaned.add (calendar);
			hpaned.add (sidebar);
			window.add (vbox);

            add_window(window);

			saved_state = new Settings.SavedState ();
			saved_state.changed["show-weeks"].connect (saved_state_show_weeks_changed);

			prefs = new Settings.MayaSettings ();
			prefs.changed["week-starts-on"].connect (prefs_week_starts_on_changed);

            handler = new Services.DateHandler();
			handler.changed.connect (date_changed);

            restore_saved_state();

            set_date ();
			date_changed();

            set_midnight_updating();
        }

		private int days_to_prepend { // TODO: will be refactored
			get {
				int days = 1 - handler.first_day_of_month + prefs.week_starts_on;
				return days > 0 ? 7 - days : -days;
			}
		}

		public void set_date (owned DateTime? date = null) { // TODO: will be tidied up
            debug ("set_date");

            if (date == null)
                date = new DateTime.now_local ();

			if (handler.current_month != date.get_month () || handler.current_year != date.get_year ())
				handler.add_full_offset (date.get_month () - handler.current_month, date.get_year () - handler.current_year);

            calendar.grid.set_date (date, days_to_prepend);
		}

        private void set_midnight_updating() {

			var today = new DateTime.now_local ();
			var tomorrow = today.add_full (0, 0, 1, -today.get_hour (), -today.get_minute (), -today.get_second ());
			var difference = tomorrow.to_unix() -today.to_unix();

			Timeout.add_seconds ((uint) difference, () => {

				if (handler.current_month == tomorrow.get_month () && handler.current_year == tomorrow.get_year ())
					calendar.grid.update_month (handler.current_month, handler.current_year, days_to_prepend);

				tomorrow = tomorrow.add_days (1);

				Timeout.add (1000 * 60 * 60 * 24, () => {
					if (handler.current_month == tomorrow.get_month () && handler.current_year == tomorrow.get_year ())
						calendar.grid.update_month (handler.current_month, handler.current_year, days_to_prepend);

					tomorrow = tomorrow.add_days (1);

					return true;
				});

				return false;
			});
        }

		private void restore_saved_state () {

            debug("Restoring saved state");
			
			// Window

			window.default_width = saved_state.window_width;
			window.default_height = saved_state.window_height;
			
			if (saved_state.window_state == Settings.WindowState.MAXIMIZED)
				window.maximize ();
			else if (saved_state.window_state == Settings.WindowState.FULLSCREEN)
				window.fullscreen ();
			
			hpaned.position = saved_state.hpaned_position;

            // Menu

			toolbar.menu.fullscreen.active = (saved_state.window_state == Settings.WindowState.FULLSCREEN);
			toolbar.menu.weeknumbers.active = saved_state.show_weeks;

            // Calendar

            calendar.weeks.update (handler.date, saved_state.show_weeks);
            calendar.header.update_columns (prefs.week_starts_on);

		}
		
		private void update_saved_state () {
			
            debug("Updating saved state");

			// Save window state
			if ((window.get_window().get_state() & Settings.WindowState.MAXIMIZED) != 0)
				saved_state.window_state = Settings.WindowState.MAXIMIZED;
			else if ((window.get_window().get_state() & Settings.WindowState.FULLSCREEN) != 0)
				saved_state.window_state = Settings.WindowState.FULLSCREEN;
			else
				saved_state.window_state = Settings.WindowState.NORMAL;
			
			// Save window size
			if (saved_state.window_state == Settings.WindowState.NORMAL) {
				int width, height;
				window.get_size (out width, out height);
				saved_state.window_width = width;
				saved_state.window_height = height;
			}
			
			saved_state.hpaned_position = hpaned.position;
		}

		private void toggle_fullscreen () {

			if (toolbar.menu.fullscreen.active)
				window.fullscreen ();
			else
				window.unfullscreen ();
		}

        //--- SIGNAL HANDLERS ---//

        private void date_changed () {
            debug("date_changed");

            calendar.header.update_columns (prefs.week_starts_on);
            calendar.weeks.update (handler.date, saved_state.show_weeks);
            calendar.grid.update_month (handler.current_month, handler.current_year, days_to_prepend);
            toolbar.month_switcher.text = handler.date.format ("%B");
            toolbar.year_switcher.text = handler.date.format ("%Y");
        }

        private void prefs_week_starts_on_changed () {
            debug("prefs_week_starts_on_changed");
            date_changed ();
        }

        private void saved_state_show_weeks_changed () {
            debug("saved_state_show_weeks_changed");

            calendar.weeks.update (handler.date, saved_state.show_weeks);
        }

        private bool window_delete_event_cb (Gdk.EventAny event) {

            update_saved_state();
            return false;
        }

        private void toolbutton_add_clicked () {

		    var add_dialog = new View.AddEventDialog (window);
		    add_dialog.show ();
        }

        private void menu_show_weeks_toggled () {

            saved_state.show_weeks = toolbar.menu.weeknumbers.active;
        }
	}

}

