import React, { useEffect, useState } from "react";
import { FiltersBar } from "./components/FiltersBar";
import { QuickToggles } from "./components/QuickToggles";
import { TechniciansTable } from "./components/TechniciansTable";
import { JobsTable } from "./components/JobsTable";

export default function App() {
	const [jobs, setJobs] = useState([]);
	const [techs, setTechs] = useState([]);

	const [jobFilter, setJobFilter] = useState("all");

	useEffect(() => {
		fetch("http://localhost:8000/jobs")
			.then((res) => res.json())
			.then(setJobs)
			.catch((err) => console.error("Error fetching jobs:", err));

		fetch("http://localhost:8000/technicians")
			.then((res) => res.json())
			.then(setTechs)
			.catch((err) => console.error("Error fetching techs:", err));
	}, []);

	const filteredJobs = jobs.filter((job) => {
		if (jobFilter === "all") return true;
		if (jobFilter === "unassigned") return job.assigned_technician_id === null;
		if (jobFilter === "soon") {
			const jobTime = new Date(job.time_window_start);
			const now = new Date();
			return (jobTime - now) / 60000 <= 30 && job.status === "pending";
		}
		return true;
	});

	return (
		<div className="min-h-screen bg-gray-100 text-gray-900 flex flex-col">
			<header className="bg-white shadow p-4 text-2xl font-bold border-b">
				FieldOpt FSM
			</header>

			<FiltersBar
				onOpenFilters={() => console.log("Open Filters Modal (stub)")}
				onAutoRoute={() => console.log("Autoroute clicked")}
				onMapView={() => console.log("Map View clicked")}
			/>

			<main className="flex-1 grid grid-rows-2 overflow-hidden">
				<section className="overflow-y-auto border-b">
					<TechniciansTable techs={techs} />
				</section>

				<section className="overflow-y-auto">
					<QuickToggles type="jobs" setFilter={setJobFilter} />
					<JobsTable jobs={filteredJobs} />
				</section>
			</main>
		</div>
	);
}
