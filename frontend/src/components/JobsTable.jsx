import React from "react";

export function JobsTable({ jobs }) {
	return (
		<div className="overflow-y-auto flex-1 border bg-white shadow rounded p-4">
			<h2 className="text-lg font-bold mb-2">Jobs</h2>
			<table className="min-w-full text-sm table-auto">
				<thead>
					<tr className="text-left border-b font-semibold">
						<th className="p-2">ID</th>
						<th className="p-2">Customer</th>
						<th className="p-2">Skill</th>
						<th className="p-2">Location</th>
						<th className="p-2">Status</th>
					</tr>
				</thead>
				<tbody>
					{jobs.map((job) => (
						<tr key={job.id} className="border-b hover:bg-gray-100">
							<td className="p-2">{job.id}</td>
							<td className="p-2">{job.customer_name}</td>
							<td className="p-2">{job.required_skill}</td>
							<td className="p-2">{job.location}</td>
							<td className="p-2 capitalize">{job.status}</td>
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}
