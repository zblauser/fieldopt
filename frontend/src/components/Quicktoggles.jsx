import React from "react";

export function QuickToggles({ type, setFilter }) {
	if (type !== "jobs") return null;

	const filters = [
		{ label: "All", value: "all" },
		{ label: "Unassigned", value: "unassigned" },
		{ label: "Near Miss", value: "soon" },
	];

	return (
		<div className="flex gap-2 bg-gray-100 px-4 py-2 border-b text-sm text-gray-700">
			{filters.map(({ label, value }) => (
				<button
					key={value}
					onClick={() => setFilter(value)}
					className="px-3 py-1 bg-white rounded hover:bg-gray-200 border"
				>
					{label}
				</button>
			))}
		</div>
	);
}
