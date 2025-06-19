import React from "react";

export function TechniciansTable({ techs }) {
	return (
		<div className="overflow-y-auto flex-1 border bg-white shadow rounded p-4">
			<h2 className="text-lg font-bold mb-2">Technicians</h2>
			<table className="min-w-full text-sm table-auto">
				<thead>
					<tr className="text-left border-b font-semibold">
						<th className="p-2">ID</th>
						<th className="p-2">Name</th>
						<th className="p-2">Location</th>
						<th className="p-2">Skills</th>
					</tr>
				</thead>
				<tbody>
					{techs.map((tech) => (
						<tr key={tech.id} className="border-b hover:bg-gray-100">
							<td className="p-2">{tech.id}</td>
							<td className="p-2">{tech.name}</td>
							<td className="p-2">{tech.location}</td>
							<td className="p-2">{tech.skills}</td>
						</tr>
					))}
				</tbody>
			</table>
		</div>
	);
}
